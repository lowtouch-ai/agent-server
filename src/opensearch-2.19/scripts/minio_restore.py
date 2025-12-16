import requests
import sys
import logging


logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
console = logging.StreamHandler()
console.setLevel(logging.INFO)
formatter = logging.Formatter('%(asctime)s - %(levelname)s - %(message)s')
console.setFormatter(formatter)
logging.getLogger('').addHandler(console)


opensearch_host = 'http://localhost:9200'
def restore_snapshot(repo_name, snapshot_number):
    """Restore the specified snapshot."""
    snapshot_name = f"snapshot_{repo_name}_{snapshot_number}"
    url = f"{opensearch_host}/_snapshot/{repo_name}/{snapshot_name}/_restore"
    try:
        response = requests.post(url)
        if response.status_code == 200:
            logging.info("Snapshot %s from repository %s restored successfully.", snapshot_name, repo_name)
        else:
            logging.error("Failed to restore snapshot %s from repository %s: %s", snapshot_name, repo_name, response.text)
    except requests.RequestException as e:
        logging.error("Failed to connect to OpenSearch at %s: %s", url, e)

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python restore_snapshot.py <repository_name> <snapshot_number>")
        sys.exit(1)

    repo_name = sys.argv[1]
    snapshot_number = sys.argv[2]

    restore_snapshot(repo_name, snapshot_number)
