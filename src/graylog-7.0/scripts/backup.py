import os
from datetime import datetime
from minio import Minio
from minio.error import S3Error
import sys
import logging

logger = logging.getLogger()
logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s', datefmt='%Y-%m-%d %H:%M:%S')

def find_latest_log_files(source_dir):
    current_date = datetime.now().strftime("%Y-%m-%d")
    all_files = os.listdir(source_dir)
    matching_files = [filename for filename in all_files if filename.startswith(f"audit.log-{current_date}")]
    return matching_files

def upload_files_to_minio(source_dir, minio_host, minio_access_key, minio_secret_key):

    minio_client = Minio(
        minio_host,
        access_key=minio_access_key,
        secret_key=minio_secret_key,
        secure=False
    )

    latest_log_files = find_latest_log_files(source_dir)

    if latest_log_files:
        logging.info(f"Latest log files for the current date: {latest_log_files}")
        minio_bucket = f"{hostname}-audit"
        if not minio_client.bucket_exists(minio_bucket):
            minio_client.make_bucket(minio_bucket)
            logging.info(f"Bucket '{minio_bucket}' created in MinIO.")
        else:
            logging.info(f"Bucket '{minio_bucket}' already exists in MinIO.")

        for file in latest_log_files:
            file_path = os.path.join(source_dir, file)
            try:
                # Upload file to MinIO bucket
                with open(file_path, 'rb') as data:
                    minio_client.put_object(minio_bucket, file, data, os.path.getsize(file_path))
                logging.info(f"File '{file}' uploaded successfully to MinIO.")
            except S3Error as e:
                logging.error(f"Error uploading file '{file}' to MinIO: {e}")
    else:
        logging.warning("No log files found for the current date.")

source_dir = "/appz/log/archive"
minio_host = os.environ.get('MINIO_HOSTNAME')
minio_access_key = os.environ.get('MINIO_ACCESS_KEY')
minio_secret_key = os.environ.get('MINIO_SECRET_KEY')
hostname = os.environ.get('HOSTNAME')

upload_files_to_minio(source_dir, minio_host, minio_access_key, minio_secret_key)
