import requests
import json
import os, subprocess
import logging, threading, re
from datetime import datetime
import boto3
from botocore.exceptions import ClientError

# Set up logging (configure once)
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger('')  # Root logger

if not logger.hasHandlers():
    console = logging.StreamHandler()
    console.setLevel(logging.INFO)
    formatter = logging.Formatter('%(asctime)s - %(levelname)s - %(message)s')
    console.setFormatter(formatter)
    logger.addHandler(console)

# MinIO and OpenSearch Configuration
minio_bucket_prefix = os.getenv('MINIO_BUCKET_NAME')
minio_endpoint = os.getenv('MINIO_ENDPOINT')
opensearch_host = 'http://localhost:9200'
minio_access_key = os.getenv('MINIO_ACCESS_KEY')
minio_secret_key = os.getenv('MINIO_SECRET_KEY')

s3_client = boto3.client('s3', endpoint_url=minio_endpoint, aws_access_key_id=minio_access_key, aws_secret_access_key=minio_secret_key)

snapshot_lock = threading.Lock()
snapshot_counters = {}

def create_bucket_and_directory(bucket_name):
    """Create a bucket and a directory for the current hour."""
    try:
        s3_client.create_bucket(Bucket=bucket_name)
        logger.info("Bucket %s created successfully.", bucket_name)
    except ClientError as e:
        if e.response['Error']['Code'] == 'BucketAlreadyOwnedByYou':
            logger.info("Bucket %s already exists.", bucket_name)
        else:
            logger.error("Error creating bucket %s: %s", bucket_name, e)
            return False
    return True

def register_repository(stream, current_hour):
    repo_name = f"{stream}_repository"
    data = {
        "type": "s3",
        "settings": {
            "bucket": bucket_name,
            "endpoint": minio_endpoint,
            "protocol": "http",
            "path_style_access": True,
            "region": "us-east-1"
        }
    }
    try:
        curl_command = f"curl -X PUT '{opensearch_host}/_snapshot/{repo_name}' -H 'Content-Type: application/json' -d '{json.dumps(data)}'"
        subprocess.run(curl_command, shell=True, check=True)

        logger.info("Repository %s registered successfully.", repo_name)
    except subprocess.CalledProcessError as e:
        logger.error("Failed to register repository %s: %s", repo_name, e)

def get_snapshot_number(repo_name):
    """Generate a unique snapshot name based on the current datetime to ensure uniqueness."""
    current_time = datetime.now().strftime('%Y%m%d%H%M%S')  # Use the current time to form a unique snapshot name
    snapshot_name = f"{repo_name}_{current_time}"
    return snapshot_name

def take_snapshot(stream, current_hour):
    """Take a snapshot for the specified stream and hour directory."""
    repo_name = f"{stream}_repository"
    snapshot_number = get_snapshot_number(repo_name)
    url = f"{opensearch_host}/_snapshot/{repo_name}/snapshot_{snapshot_number}?wait_for_completion=true"
    data = {
        "indices": f"{stream}",
        "ignore_unavailable": True,
        "include_global_state": False
    }
    try:
        response = requests.put(url, json=data)
        if response.status_code == 200:
            logger.info("Snapshot for %s taken successfully.", stream + "-" + current_hour)
        else:
            logger.error("Failed to take snapshot for %s: %s", stream + "-" + current_hour, response.text)
    except requests.RequestException as e:
        logger.error("Failed to connect to OpenSearch at %s: %s", url, e)

def get_all_indices():
    """Retrieve all index names from OpenSearch."""
    url = f"{opensearch_host}/_cat/indices?v"
    recent_index = []  
    try:
        response = requests.get(url)
        if response.status_code == 200:
            lines = response.text.strip().split('\n')
            headers = lines[0].split()
            index_name_pos = headers.index('index')
            graylog_indices = [
                line.split()[index_name_pos] for line in lines[1:]
                if line.split()[index_name_pos].startswith('graylog_')
            ]

            index_pattern = re.compile(r'^graylog_(\d+)$')
            numbered_indices = [(int(index_pattern.search(idx).group(1)), idx) for idx in graylog_indices if index_pattern.search(idx)]
            logger.info("numbered_indices: " + str(numbered_indices))

            if numbered_indices:
                sorted_indices = sorted(numbered_indices, key=lambda x: x[0], reverse=True)
                if len(sorted_indices) > 2:
                    most_recent_index = sorted_indices[2][1]
                    logger.info("most_recent_index: " + most_recent_index)
                    recent_index.append(most_recent_index)
                else:
                    logger.info("Less than three 'graylog_' prefixed indices with numerical suffix found, no third most recent index to return.")
            else:
                logger.info("No 'graylog_' prefixed indices with numerical suffix found.")
        else:
            logger.error("Failed to list indices: %s", response.text)
    except requests.RequestException as e:
        logger.error("Failed to retrieve indices from OpenSearch: %s", e)

    logger.info("returning recent_index: " + str(recent_index))
    return recent_index

if __name__ == "__main__":
    pod_index = os.environ.get('HOSTNAME', '').split('-')[-1]
    if pod_index == "0":
        date = datetime.now().strftime('%Y-%m-%d')
        current_hour = datetime.now().strftime('%Y.%m.%d.%H')
        bucket_name = f"{minio_bucket_prefix}-{date}"
        if create_bucket_and_directory(bucket_name):
            index_streams = get_all_indices()
            for stream in index_streams:
                register_repository(stream, current_hour)
                take_snapshot(stream, current_hour)
    else:
        print(f"This pod ({pod_index}) does not perform the snapshot tasks, skipping")
