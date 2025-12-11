#!/bin/bash
exec /usr/local/bin/apache_exporter \
  --scrape_uri="http://127.0.0.1/server-status?auto"

