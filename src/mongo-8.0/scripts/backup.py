#!/usr/bin/python
import os, sys, tarfile, os.path, logging, pytz, datetime, time, subprocess, boto3
from pymongo import MongoClient
from bson.json_util import dumps
from dotenv import load_dotenv
load_dotenv()
logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s', datefmt='%Y-%m-%d %H:%M:%S')


def check_db():

    directory = (f'/appz/backup')
    if not os.path.exists(directory):
        os.makedirs(directory)
    return directory

def render_output_locations():

    directory1 = (f'/appz/backup')
    if not os.path.exists(directory1):
        os.makedirs(directory1)
    return directory1

def s3_backup():
    session = boto3.Session(
    aws_access_key_id=aws_access_key_id,
    aws_secret_access_key=aws_secret_access_key,
    region_name=region_name
    )

    s3 = session.client("s3")

    backup_files_str = os.environ.get('BACKUPFILE', '')
    backup_files = backup_files_str.split(',')
    for backup_file in backup_files:
     command = f'aws s3 sync /appz/backup/ s3://{s3_bucket}/ --exclude "*" --include "{backup_file}_*.gz.enc"'

     result = subprocess.run(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

     output = result.stdout

     if "upload:" in output and result.returncode == 0:

           logging.info('%s %s' % (backup_file, 'Uploaded to s3'))
     else:

          logging.warning('%s %s' % (backup_file, 'Failed to upload to s3'))
          raise Exception(f"{result.stderr}")

def run_backup(mongoUri):
    time_utc = pytz.utc.localize(datetime.datetime.utcnow())
    covert_time = time_utc.strftime('%Y-%m-%dT%H:%M:%SZ')
    directory1 = check_db()

    client = MongoClient(mongoUri)
    dbnames = client.list_database_names()
    for dbs in dbnames:
     if dbs in ["config", "admin", "local"]:
        continue

     file_name1 = (f'{directory1}/{dbs}_{covert_time}.gz')
     command = f'mongodump --uri {mongoUri} --host {host} --port {port} --db {dbs} --gzip --archive="{file_name1}"'
     process = subprocess.run(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
     if enable_dump == "1":
       logging.info(process.stderr)


     if process.returncode == 0:
                    logging.info('%s %s' % (dbs,
                        'Database Backup Sucessfull'))


     else:
                    logging.warning('%s %s' % (dbs,
                        'Database Backup Failed'))
     if replication != 0 and auth_enable != 0:

        openssldb_cmd = [
         "openssl",
         "enc",
         "-e",
         "-aes-256-cbc",
         "-md",
         "sha512",
         "-pbkdf2",
         "-iter",
         "100000",
         "-salt",
         "-k",
         encryption_key,
         "-in",
         file_name1,
         "-out",
         file_name1 + ".enc"
        ]

        openssl_result1 = subprocess.run(openssldb_cmd)
        if openssl_result1.returncode == 0:
           os.remove(file_name1)
           logging.info('%s %s' % (dbs,
                        'DB backup encrypted'))

        else:
           logging.warning('%s %s' % (dbs,
                        'Encryption Failed'))



def encrypted_allbackup(wholedb_backup):
   time_utc = pytz.utc.localize(datetime.datetime.utcnow())
   covert_time = time_utc.strftime('%Y-%m-%dT%H:%M:%SZ')
   directory1 = render_output_locations()
   file_name = (f'{directory1}/{wholedb_backup}_{covert_time}.gz')
   mongodump_cmd = ["mongodump", "--uri", mongoUri, "--gzip", "--archive=" + file_name]
   process1 = subprocess.run(mongodump_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
   if enable_dump == "1":
    logging.info(process1.stderr)

   if process1.returncode == 0:
                    logging.info('%s %s' % ('Whole Database',
                        'Backup Sucessfull Proceeding with encryption'))

   else:
                    logging.warning('%s %s' % ('Whole Database',
                        'Database Backup Failed'))

   openssl_cmd = [
    "openssl",
    "enc",
    "-e",
    "-aes-256-cbc",
    "-md",
    "sha512",
    "-pbkdf2",
    "-iter",
    "100000",
    "-salt",
    "-k",
    encryption_key,
    "-in",
    file_name,
    "-out",
    file_name + ".enc"
]

   openssl_result = subprocess.run(openssl_cmd)
   if openssl_result.returncode == 0:
    os.remove(file_name)

    logging.info('%s %s' % ('Whole Database',
                        'Backup encrypted'))

   else:
    logging.warning('%s %s' % ('ERROR',
                        'Whole Database Backup encryption Failed'))

if __name__ == '__main__':

        time_utc = pytz.utc.localize(datetime.datetime.utcnow())
        covert_time = time_utc.strftime('%Y-%m-%dT%H:%M:%SZ')
        encryption_key = os.environ.get('ENCRYPTION_KEY')
        username = os.environ.get('DB_USER_ADMIN')
        password = os.environ.get('DB_USER_ADMIN_PASSWORD')
        host = os.environ.get('MONGODB_HOST')
        port = os.environ.get('MONGODB_PORT')
        replication = int(os.getenv('REPLICATION', 0))
        auth_enable = int(os.getenv('AUTH_ENABLE', 0))
        if replication == 0 and auth_enable == 0:
            mongoUri = (f'mongodb://{host}:{port}/')
        else:
            if username is None:
                   logging.warning('%s %s' % ('ERROR',
                        ' DB_USER_ADMIN not found from env'))
                   sys.exit(1)
            if password is None:
                   logging.warning('%s %s' % ('ERROR',
                        ' DB_USER_ADMIN_PASSWORD not found from vault'))
                   sys.exit(1)
            mongoUri = (f'mongodb://{username}:{password}@{host}:{port}/?authSource=admin')
        aws_access_key_id = os.environ.get('AWS_ACCESS_KEY_ID')
        aws_secret_access_key = os.environ.get('AWS_SECRET_ACCESS_KEY')
        region_name = os.environ.get('AWS_DEFAULT_REGION')
        s3_bucket = os.environ.get('S3_BUCKET')
        backup_file = os.environ.get('BACKUPFILE')
        enable_dump = os.environ.get('ENABLE_DUMPLOG', "0")

        if host is None:
         logging.warning('%s %s' % ('ERROR',
                        ' MONGODB_HOST not found from env'))

         sys.exit(1)


        if port is None:
         logging.warning('%s %s' % ('ERROR',
                        ' MONGODB_PORT  not found from env'))


         sys.exit(1)


        try:
            run_backup(mongoUri)
            logging.info('%s %s' % ('STATUS',
                          'Successfully Completed MongoDb Backup Without auth'))

            if replication != 0 and auth_enable != 0:

                  if encryption_key is None:
                        logging.warning('%s %s' % ('ERROR',
                                ' ENCRYPTION_KEY not found from env'))
                        sys.exit(1)
                  encrypted_allbackup("alldb")
                  s3_backup()
        except Exception as e:
            logging.error('%s %s' % ('Backup Failed', str(e)))
