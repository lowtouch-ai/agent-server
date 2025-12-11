import git
import os
import shutil
import logging
import json
import time
import smtplib
import yaml
from pathlib import Path
from email.message import Message
from datetime import datetime
from urllib.parse import urlparse, urlunparse
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart


logfile = os.environ.get('GIT_RUNNER_LOGFILE','/appz/log/git_runner.log')
smtp = os.environ.get('GIT_RUNNER_SMTP_ENABLED', False)

logging.basicConfig(filename= logfile, filemode='a', format='{"time": "%(asctime)s", "level": "%(levelname)s",  "msg": "%(message)s"}',level=logging.INFO)
logger = logging.getLogger()

if str(smtp).lower() == "true":

    smtp = True
    logger.info(f"SMTP enabled for notifications")

    smtp_host = os.environ.get('GIT_RUNNER_SMTP_HOST')
    smtp_port = os.environ.get('GIT_RUNNER_SMTP_PORT')
    smtp_timeout = os.environ.get('GIT_RUNNER_SMTP_TIMEOUT', 10)
    smtp_user = os.environ.get('GIT_RUNNER_SMTP_USER', None)
    smtp_password = os.environ.get('GIT_RUNNER_SMTP_PASSWORD', None)
    smtp_from = os.environ.get('GIT_RUNNER_SMTP_FROM')

    for i,j in [("SMTP_HOST",smtp_host), ("SMTP_PORT",smtp_port), ("SMTP_FROM",smtp_from)]:
        
        if j is None:
            logger.error(f"{i} not found from env")
            exit(1)


def mask_password(url):
    parsed_url = urlparse(url)
    
    if parsed_url.password:
        masked_netloc = parsed_url.netloc.replace(parsed_url.password, "****")
    else:
        masked_netloc = parsed_url.netloc

    masked_url = urlunparse(parsed_url._replace(netloc=masked_netloc))
    return masked_url


def is_git_repo(path):

    try:
        _ = git.Repo(path).git_dir
        logger.info(f"repo exists in path {path}")
        return True
    except git.exc.InvalidGitRepositoryError:
        logger.warning(f"repo did not exists in path {path}")
        return False


def is_git_repo_upto_date(repo,remote_branch):
    try:
        repo.remotes.origin.fetch()
    except Exception as err:
        logger.error(f"ERROR occured while Fetching remote origin for {repo}\n{str(err)}")
        if os.path.exists(repo.working_tree_dir) and os.environ.get('GIT_RUNNER_PURGE_ON_FETCH_ERROR',False):
            shutil.rmtree(repo.working_tree_dir)
            logger.warning(f"resetting working tree dir {repo.working_tree_dir}")
            return True
    else:
        diff = str(repo.git.diff(f'origin/{remote_branch}')).splitlines()

        if len(diff) != 0:
            logger.info(f"found changes in upstream wrt working head")
            return False
        else:
            return True


def update_git_repo(repo, remote_branch):
    try:
        logger.info(f"stashing current changes")
        repo.git.stash('push', '--include-untracked')
        logger.warning(f"resetting head")
        repo.git.reset('--hard',f'origin/{remote_branch}')
        repo.git.clean('-fd')
        logger.info(f"pulling repo")
        remote_repo = repo.remote()
        remote_repo.pull(remote_branch)
        smtp_status = "SUCCESS"
        latest_commit = repo.commit(f'origin/{remote_branch}')
        commit_details = {"Commit Hash": latest_commit.hexsha, "Author": latest_commit.author.name, "Message": latest_commit.message.strip()}
        logger.info(commit_details)
    except Exception as err:
        smtp_status = "FAILED"
        logger.error(f"ERROR occured while updating repo {repo}\n{str(err)}")
    finally:
        if commit_details is not None:
            return smtp_status, datetime.now(), commit_details
        else:
            return smtp_status, datetime.now()


def copy_dag_to_subdirectories(repo, base_dir, dag_to_copy, file_name):
    # Check if the file exists in the remote repository
    if file_name in repo.git.ls_files():
        logger.info(f"{file_name} exists in repo")
        base_directory_path = os.path.dirname(os.path.abspath(dag_to_copy))
        parent_directory_path = os.path.dirname(base_directory_path)
        if base_dir == parent_directory_path:
            logger.info(f"skipping copy in {parent_directory_path}")
            return
        else:
            file_name = os.path.join(base_dir, file_name)
            with open(file_name, "r") as file:
                config = yaml.safe_load(file)
            if 'SCHEMAS' in config and config['SCHEMAS']:
                schemas = config['SCHEMAS']
                logger.info(f"SCHEMAS found in {file_name}: {schemas}")
                copied = {}

                for schema in schemas:
                    schema_dir = os.path.join(base_dir, schema)

                    if os.path.exists(schema_dir) and os.path.isdir(schema_dir):
                        destination = os.path.join(schema_dir, os.path.basename(dag_to_copy))
                        if os.path.exists(destination):
                            logger.info(f"Skipped copying {dag_to_copy} to {schema_dir} as {os.path.basename(dag_to_copy)} already exists")
                            copied[schema_dir] = False
                        else:
                            shutil.copyfile(dag_to_copy, destination)
                            logger.info(f"Copied {dag_to_copy} to {schema_dir}")
                            copied[schema_dir] = True
                    else:
                        logger.warning(f"Schema directory {schema_dir} does not exist.")
                        copied[schema_dir] = "Schema Does not Exists in Repo"
                return {key: value for key, value in copied.items() if value is not True}
                 
            else:
                logger.info(f"No SCHEMAS found in {file_name}, copying to all subdirectories")
                copied = {}

                for subdir in os.listdir(base_dir):
                    subdir_path = os.path.join(base_dir, subdir)

                    if os.path.isdir(subdir_path) and not subdir.startswith(('.', '__')):
                        destination = os.path.join(subdir_path, os.path.basename(dag_to_copy))
                        if os.path.exists(destination):
                            logger.info(f"Skipped copying {dag_to_copy} to {subdir_path} as {os.path.basename(dag_to_copy)} already exists")
                            copied[subdir_path] = False
                        else:
                            shutil.copyfile(dag_to_copy, destination)
                            logger.info(f"Copied {dag_to_copy} to {subdir_path}")
                return copied
    else:
        logger.info(f"{file_name} does not exist in repo")


def send_email(to, subject, status, repo, branch, timestamp, **kwargs):
    
    if smtp is not None and smtp:

        if isinstance(to, str):
            to = [to]

        server = smtplib.SMTP(smtp_host, smtp_port, timeout=int(smtp_timeout))
        if smtp_user is not None and smtp_password is not None:
            server.login(smtp_user, smtp_password)

        msg = MIMEMultipart("alternative")
        msg['From'] = smtp_from
        msg['To'] = ', '.join(to)
        msg['Subject'] = f"{subject} deployment {status.lower()}"

        html_payload = f"""\
        <html>
        <body>
            <p><span style="font-weight: 800;"><strong>Repo:</strong></span> {repo}</p>
            <p><span style="font-weight: 800;"><strong>Branch:</strong></span> {branch}</p>
            <p><span style="font-weight: 800;"><strong>Status:</strong></span> <span style="color:{'green' if status.lower() == 'success' else 'red'};">{status}</span></p>
            <p><span style="font-weight: 800;"><strong>Timestamp:</strong></span> {timestamp}</p>
        """
        
        if "commit_details" in kwargs:
            html_payload += f"""<p><span style="font-weight: 800;"><strong>Commit Details:</strong></span> {kwargs['commit_details']}</p>"""
        
        if "copied" in kwargs and kwargs['copied']:
            html_payload += f"""<p><span style="font-weight: 800;"><strong>Snowflake Objects DAG Copy Status:</strong></span><br>"""
            for key, value in kwargs['copied'].items():
                if value is False:
                    html_payload += f"{key}: <span style='color:blue;'>Skipping Copy as File already Exists</span><br>"
                else:
                    html_payload += f"{key}: <span style='color:red;'>{value}</span><br>"
            html_payload += "</p>"
        
        html_payload += "</body></html>"

        msg.attach(MIMEText(html_payload, "html"))

        server.sendmail(smtp_from, to, msg.as_string())
        server.quit()    
        return


def delete_directory_contents(path: Path):
    if not path.exists() or not path.is_dir():
        return

    for item in path.iterdir():
        if item.is_dir():
            delete_directory_contents(item)
            item.rmdir()
        else:
            item.unlink()


def delete_directory(path: Path):
    if path.exists() and path.is_dir():
        delete_directory_contents(path)
        path.rmdir()
        logger.warning(f"Directory {path} and its contents have been deleted.")
    else:
        logger.warning(f"Directory {path} does not exist or is not a directory.")


def get_repo_list(git_url, user, token, repos, dag_to_copy, object_ci_yaml_to_check):
    
    try:

        for repo in repos.items():
            
            if repo[0].startswith("https://"):
                if user is not None and token is not None:
                    git_clone_url = repo[0].replace("//",f"//{user}:{token}@")
                else:
                    git_clone_url = repo[0]

                remote_url = f"{git_clone_url}.git"
                log_remote_url = f"{repo[0]}"
                smtp_subject = repo[0].split("/")
                smtp_subject = f"{smtp_subject[-2]}/{smtp_subject[-1]}"
            else:
                if user is not None and token is not None:
                    git_clone_url = git_url.replace("//",f"//{user}:{token}@")
                else:
                    git_clone_url = git_url

                remote_url = f"{git_clone_url}{repo[0]}.git"
                log_remote_url = f"{git_url}{repo[0]}"
                smtp_subject = git_url.split("/")[-2]
                smtp_subject = f"{smtp_subject}/{repo[0]}"
            
            masked_url = mask_password(remote_url)
            path_to_clone = repo[1]["path"]
            remote_branch = repo[1]["branch"]
            smtp_to = repo[1]["email"]
            smtp_status =''
            logger.info(f"remote_url: {masked_url}")
            logger.info(f"log_remote_url: {log_remote_url}")
            logger.info(f"smtp_subject: {smtp_subject}")
            logger.info(f"path_to_clone: {path_to_clone}")
            logger.info(f"remote_branch: {remote_branch}")
            
            if path_to_clone is None:
                logger.error(f"cloning destination can not be empty for {repo}")
            
            if not os.path.exists(path_to_clone):
                logger.warning(f"path did not exists! creating path {path_to_clone}")
                Path(path_to_clone).mkdir(parents=True, exist_ok=True)
            
            if os.path.isdir(path_to_clone):
                
                if is_git_repo(path_to_clone):

                    try:
                        git_repo = git.Repo(path_to_clone, search_parent_directories=True)
                        logger.info(f"found repo {git_repo}")
                    except:
                        logger.error(f"could not find a repo in path {path_to_clone}")
                    try:
                        if is_git_repo_upto_date(git_repo, remote_branch):
                            logger.info(f"repo upto date, nothing to pull")
                        else:
                            smtp_status, timestamp, commit_details = update_git_repo(git_repo, remote_branch)
                            copied = copy_dag_to_subdirectories(git_repo, path_to_clone, dag_to_copy, object_ci_yaml_to_check)
                            smtp_status = "SUCCESS" if not copied else "FAILED"
                            send_email(smtp_to, smtp_subject, smtp_status, log_remote_url, remote_branch, timestamp, commit_details = commit_details, copied = copied)
                    except Exception as err:
                        logger.error(f"ERROR occured while updating repo {git_repo}\n{str(err)}")
                else:
                    logger.info(f"cloning into repo {log_remote_url}.git")
                    try:
                        git.Repo.clone_from(remote_url, path_to_clone, branch=remote_branch)   #clone repo
                        smtp_status = "SUCCESS"
                        timestamp =  datetime.now()
                    except Exception as err:
                        smtp_status = "FAILED"
                        timestamp =  datetime.now()
                        logger.error(f"cloning into repo {log_remote_url}.git FAILED!\n{str(err)}")
                    else:
                        git_repo = git.Repo(path_to_clone, search_parent_directories=True)
                        copied = copy_dag_to_subdirectories(git_repo, path_to_clone, dag_to_copy, object_ci_yaml_to_check)
                        smtp_status = "SUCCESS" if not copied else "FAILED"
                    finally:
                        send_email(smtp_to, smtp_subject, smtp_status, log_remote_url, remote_branch, timestamp, copied = copied)
            else:
                logger.error(f"ValueError : not a valid directory ")
                raise ValueError("not valid directory")
    except Exception as err:
        logger.error(f"ERROR occured while updating repo list\n{str(err)}")


def main():

    try:
        git_url = os.environ.get('GIT_RUNNER_REMOTE_URL')
        user = os.environ.get('GIT_RUNNER_USER_NAME')
        token = os.environ.get('GIT_RUNNER_ACCESS_TOKEN')
        interval = float(os.environ.get('GIT_RUNNER_POLL_INTERVAL', 60))
        alt_repo = os.environ.get('REPOS_JSON_URL')
        repofile = '/appz/scripts/repos.json'
        alt_repo_mail = os.environ.get('REPOS_JSON_NOTIFICATION_EMAIL')
        purge_repos = os.environ.get('GIT_RUNNER_PURGE_REPOS')
        dag_to_copy = os.environ.get('GIT_RUNNER_DAG_TO_COPY', '/appz/scripts/template_dag.py')
        object_ci_yaml_to_check = 'snowflake_ci.yml'

        
        if purge_repos is not None:
            logger.info(f"path for clean up are {purge_repos}")
            if isinstance(purge_repos, str):
                purge_repos = purge_repos.split(',')
            for path in purge_repos:
                try:
                    path_to_delete = Path(path)
                    logger.info(f"proceeding to remove directory{path}")
                    delete_directory(path_to_delete)
                except Exception as err:
                    logger.error(f"ERROR occured while deleting directory{path}\n{str(err)}")
        
        if git_url is None:
            logger.error(f"GIT_RUNNER_REMOTE_URL not found from env")
            return
        
        if user is None:
            logger.error(f"GIT_RUNNER_USER_NAME not found from env")
        
        if token is None:
            logger.error(f"GIT_RUNNER_ACCESS_TOKEN not found from env")
        
        if alt_repo is None:
            logger.warning(f"REPOS_JSON_URL not found from env, using default repos file to sync.")
            with open(repofile) as file:
                repos = file.read()
                repos = json.loads(repos)
                if repos is None:
                    logger.error(f"repofile is empty!")
                    return
            
            while True:
                get_repo_list(git_url, user, token, repos, dag_to_copy, object_ci_yaml_to_check)
                time.sleep(interval)
        else:
            logger.warning(f"Using repos file from {alt_repo} to sync.")
            repo_path = '/appz/data/repos/'
            parts = alt_repo.split('.git', 1)
            remote_url = parts[0] + '.git'
            if user is not None and token is not None:
                    remote_url = remote_url.replace("//",f"//{user}:{token}@")
                    masked_url = mask_password(remote_url)    
            branch_name = parts[1].lstrip('/') if len(parts) > 1 else ''
            file_to_pull = 'repos.json'
            smtp_subject = remote_url.split(".git")[0].split('/')
            smtp_subject = f"{smtp_subject[-2]}/{smtp_subject[-1]}/{file_to_pull}"
            log_remote_url = parts[0]

            if not os.path.exists(repo_path):
                repo = git.Repo.clone_from(remote_url, repo_path, no_checkout=True, branch=branch_name)
            else:
                repo = git.Repo(repo_path)
                current_branch = repo.active_branch.name
                if current_branch != branch_name:
                    repo.git.checkout(branch_name)
            
            repo.git.config('core.sparseCheckout', 'true')

            sparse_checkout_file = os.path.join(repo_path, '.git', 'info', 'sparse-checkout')
            with open(sparse_checkout_file, 'w') as file:
                file.write(file_to_pull)
            repo.git.checkout(branch_name)

            def pull_repo_file(repo, branch_name, file_to_pull):
                repo.remotes.origin.fetch()
                
                changes = str(repo.git.diff(f'origin/'+ branch_name, file_to_pull))
                if changes:
                    logger.warning(f"Changes detected in {file_to_pull}{changes}. Updating local file.")
                    try:
                        repo.git.checkout('origin/' + branch_name, file_to_pull)
                        smtp_status = "SUCCESS"
                        timestamp =  datetime.now()
                    except Exception as err:
                        smtp_status = "FAILED"
                        timestamp =  datetime.now()
                        logger.error(f"Updating local file {file_to_pull} FAILED!\n{str(err)}")
                    finally:
                        if alt_repo_mail is not None:
                            send_email(alt_repo_mail, smtp_subject, smtp_status, log_remote_url, branch_name, timestamp)

                else:
                    logger.info(f"No changes detected in {file_to_pull}.")
            
            while True:
                pull_repo_file(repo, branch_name, file_to_pull)
                repofile = f"{repo_path}{file_to_pull}"
                with open(repofile) as file:
                    repos = file.read()
                    repos = json.loads(repos)
                    if repos is None:
                        logger.error(f"repofile is empty!")
                        return
                get_repo_list(git_url, user, token, repos, dag_to_copy, object_ci_yaml_to_check)
                time.sleep(interval)

    except Exception as err:
        logger.error(f"{str(err)}")


if __name__ == "__main__":

    main()
