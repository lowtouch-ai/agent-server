from prometheus_client import start_http_server
import time
import threading

if __name__ == '__main__':
    # Start the Prometheus metrics server on port 8001
    start_http_server(8001)
    print("Prometheus metrics server started at http://localhost:8001")

    # Keep the script running
    print("Generic Python exporter running...")
    while True:
        time.sleep(10)
