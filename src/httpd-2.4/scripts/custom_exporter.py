#!/usr/bin/env python3

import requests
import time
from prometheus_client import start_http_server, Gauge

VHOSTS = {
    "adminer2025a.lowtouch.ai": "http://192.168.61.100:8090",
    "airflow2025a.lowtouch.ai": "http://192.168.61.100:8081",
    "airflow2025b.lowtouch.ai": "http://192.168.61.100:8081",
    "api2025a.lowtouch.ai": "http://192.168.61.100:8000/webshop/docs",
    "api2025b.lowtouch.ai": "http://192.168.61.100:8000/webshop/docs",
    "auth2025.lowtouch.ai": "http://192.168.61.100:8090",
    "demo2025a.lowtouch.ai": "http://192.168.61.100:8080",
    "demo2025b.lowtouch.ai": "http://192.168.61.100:8080",
    "grafana2025a.lowtouch.ai": "http://192.168.61.100:3000",
    "graylog2025a.lowtouch.ai": "http://192.168.61.100:9000",
    "sitechime2025a.lowtouch.ai": "http://192.168.61.100:3001"
}

TIMEOUT = 30

vhost_up = Gauge('apache_vhost_up', 'Whether the Apache virtual host is up (1) or down (0) based on backend HTTP response', ['vhost'])

def check_vhost_status(vhost, url):
    try:
        response = requests.get(url, timeout=TIMEOUT)
        print(f"{vhost} responded with status {response.status_code} from {url}")
        return 1  # Up if any response is received (including 301)
    except requests.Timeout:
        print(f"{vhost} down: Timeout exceeded for {url} after {TIMEOUT}s")
        return 0
    except requests.ConnectionError as e:
        print(f"{vhost} down: Connection error for {url} - {str(e)}")
        return 0
    except requests.RequestException as e:
        print(f"{vhost} down: Unexpected error for {url} - {str(e)}")
        return 0

def update_metrics():
    while True:
        for vhost, url in VHOSTS.items():
            status = check_vhost_status(vhost, url)
            vhost_up.labels(vhost=vhost).set(status)
        time.sleep(10)

if __name__ == '__main__':
    start_http_server(9118)
    print("Serving metrics on http://localhost:9118/metrics")
    update_metrics()
