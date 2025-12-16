import re
import logging
import time
from prometheus_client import Gauge, Counter, start_http_server, Info
import tailer
import socket
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor
from threading import Lock

host = socket.getfqdn()
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s %(levelname)s %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S',
    handlers=[logging.FileHandler('/appz/log/custom_metrics.log', mode='a', encoding='utf-8')]
)

active_sessions = Gauge('active_sessions', 'Number of active sessions', ['user', 'host'])
failed_attempts = Gauge('failed_attempts', 'Current number of failed login attempts', ['user', 'host'])
last_failed_login_info = Info('last_failed_login_info', 'Info about the last failed login attempt')
sudo_commands_counter = Counter('sudo_commands_usage', 'Number of sudo commands executed', ['user', 'host'])
unique_ip_counter = Counter('ssh_login_attempts', 'SSH login attempts by IP and method', ['ip', 'login_method', 'user', 'host'])
user_addition_info = Gauge('user_addition', 'Information on user addition', ['user', 'host', 'time'])
user_modification_info = Gauge('user_modification', 'Information on user modification', ['user', 'host', 'time', 'action'])
user_deletion_info = Gauge('user_deletion', 'Information on user deletion', ['user', 'host', 'time'])
password_changes_info = Gauge('password_change', 'Information on password changes', ['user', 'host', 'time'])
file_access_attempts = Counter('file_access_attempts', 'File open access attempts', ['filepath', 'host'])
user_details = Info('user_details', 'Information about user accounts', ['user', 'host'])
password_expiry_details = Info('password_expiry_details', 'Details of user password expiry', ['user', 'host'])

active_sessions_tracker = {}
failed_attempts_tracker = {}
data_lock = Lock()

def clean_filepath(filepath_tuple):
    if filepath_tuple and isinstance(filepath_tuple, tuple) and len(filepath_tuple) == 1:
        filepath_str = filepath_tuple[0] 
        clean_path = re.sub(r"\('|\',\)|'", "", filepath_str)
        return clean_path
    return ""

def handle_audit_log(line):
    file_access_pattern = re.compile(r"type=PATH msg=audit\(\d+\.\d+:.*?\): item=0 name=\"(.*?)\" .*?")
    file_access_match = file_access_pattern.search(line)
    if file_access_match:
        filepath_tuple = file_access_match.groups()
        cleaned_filepath = clean_filepath(filepath_tuple)
        with data_lock:
            file_access_attempts.labels(filepath=cleaned_filepath, host=host).inc()
        logging.info(f"File access attempt: Path - {cleaned_filepath}")

pam_patterns = {
        'pam_success': re.compile(r"Starting session: shell on pts/\d+ for (\w+) from"),
        'pam_failed': re.compile(r"Failed publickey for (\w+) from ([\d\.]+) port \d+ ssh2"),
        'pam_close': re.compile(r"session closed for user (\w+)"),
        'sudo_command': re.compile(r"sudo: +(\w+) +: TTY"),
        'ssh_login': re.compile(r"Accepted (password|publickey) for (\w+) from ([\d\.]+) port \d+ ssh2"),
        'user_add': re.compile(r"(\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2}).*?useradd.*?:\s+new user: name=(\w+),"),
        'user_mod': re.compile(r"(\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2})\s+.*usermod\[\d+\]:\s+(.*)"),
        'user_del': re.compile(r"(\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2})\s+.*userdel\[\d+\]:\s+delete user\s+'(\w+)'"),
        'password_change': re.compile(r"(\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2})\s+.*passwd\[\d+\]:\s+pam_unix\(passwd:chauthtok\):\s+password\s+changed\s+for\s+(\w+)"),
        'user_info': re.compile(r"userac-info: User: ([\w_]+), UID: (\d+), Groups: ([\w\s_]+), Last Login: (.*), Status: (Logged in|Not logged in), Created:\s+(\w+\s+\d{1,2}\s+\d{4}\s+\d{2}:\d{2}:\d{2})"),
        'password_expiry': re.compile(r"expiry-info: User: (\S+), Expiry Info:.*Last password change.*: (\w+ \d+, \d{4}).*Password expires.*: (\w+ \d+, \d{4}|never).*Maximum number of days between password change.*: (\d+)")
}        

def process_combined_log_entry(line):
    for key, pattern in pam_patterns.items():
        match = pattern.search(line)
        if match:
            with data_lock:
                handle_pam_logs(key, match)

def handle_pam_logs(key, match):
    user = match.group(1)
    if key == 'pam_success':
        active_sessions_tracker[user] = active_sessions_tracker.get(user, 0) + 1
        active_sessions.labels(user=user, host=host).set(active_sessions_tracker[user])
        logging.info(f"Session started for user {user}. Active sessions now: {active_sessions_tracker[user]}")
    elif key == 'pam_failed':
        ip = match.group(2)
        failed_attempts_tracker[user] = failed_attempts_tracker.get(user, 0) + 1
        failed_attempts.labels(user=user, host=host).set(failed_attempts_tracker[user])
        last_failed_login_info.info({'user': user, 'ip': ip, 'host': host, 'time': time.strftime('%Y-%m-%d %H:%M:%S')})
        logging.info(f"Failed login attempt for user {user} from IP {ip}.")
    elif key == 'pam_close':
        if user in active_sessions_tracker and active_sessions_tracker[user] > 0:
            active_sessions_tracker[user] -= 1
            active_sessions.labels(user=user, host=host).set(active_sessions_tracker[user])
            logging.info(f"Session ended for user {user}.")
    elif key == 'sudo_command':
        sudo_commands_counter.labels(user=user, host=host).inc()
        logging.info(f"Sudo command used by user {user}.")
    elif key == 'ssh_login':
        login_method, username, ip = match.groups()
        unique_ip_counter.labels(ip=ip, login_method=login_method, user=username, host=host).inc()
        logging.info(f"SSH login attempt by {username} from IP {ip} using {login_method}.")
    elif key == 'user_info':
        users_processed = set()
        user, uid, groups, last_login, status, created = match.groups()
        groups = ', '.join(groups.split())
        if user not in users_processed:
            user_details.labels(user=user, host=host).info({'uid': uid, 'groups': groups, 'last_login': last_login, 'status': status, 'created': created})
            logging.info(f"Processed user details for {user}. UID: {uid}, Groups: {groups}, Last Login: {last_login}, Status: {status}, Created: {created}.")
            users_processed.add(user)
    elif key == 'password_expiry':
        user, last_change_str, expires_str, max_days_str = match.groups()
        last_change_date = datetime.strptime(last_change_str, '%b %d, %Y').strftime('%Y-%m-%d')
        expires = 'never' if expires_str.lower() == 'never' else datetime.strptime(expires_str, '%b %d, %Y').strftime('%Y-%m-%d')
        password_expiry_details.labels(user=user, host=host).info({'last_change': last_change_date, 'expires': expires, 'max_days_between_change': max_days_str})
        logging.info(f"Password expiry for {user}: Last change {last_change_date}, Expires {expires}.")
    elif key in ['user_add', 'user_mod', 'user_del', 'password_change']:
        datetime_str, user = match.groups()
        log_time = datetime.strptime(datetime_str + " " + str(datetime.now().year), "%b %d %H:%M:%S %Y")  # Adjust format as needed
        formatted_time = log_time.strftime('%Y-%m-%d %H:%M:%S')
        if key == 'user_add':
            user_addition_info.labels(user=user, host=host, time=formatted_time).set(1)
            logging.info(f"New user added: {user}, time: {formatted_time}.")
        elif key == 'user_mod':
            datetime_str, mod_action = match.groups()
            user_modification_info.labels(user=user, host=host, time=formatted_time, action=mod_action).set(1)
            logging.info(f"User account modified: {user}, time: {formatted_time}, action: {mod_action}.")
        elif key == 'user_del':
            user_deletion_info.labels(user=user, host=host, time=formatted_time).set(1)
            logging.info(f"User deleted: {user}, time: {formatted_time}.")
        elif key == 'password_change':
            password_changes_info.labels(user=user, host=host, time=formatted_time).set(1)
            logging.info(f"Password changed: {user}, time: {formatted_time}.")

def tail_log_file(file_path, callback):
    try:
        for line in tailer.follow(open(file_path)):
            callback(line)
    except Exception as e:
        logging.error(f"Failed to tail log file {file_path}: {e}")

if __name__ == "__main__":
    pam_log_path = '/appz/log/auth.log'
    audit_log_path = '/appz/log/audit/audit.log'
    start_http_server(8000)
    logging.info("Metrics server running on http://localhost:8000")

    with ThreadPoolExecutor(max_workers=2) as executor:
        executor.submit(tail_log_file, pam_log_path, process_combined_log_entry)
        executor.submit(tail_log_file, audit_log_path, handle_audit_log)

    logging.info("Log monitoring started successfully for both PAM and audit logs.")

