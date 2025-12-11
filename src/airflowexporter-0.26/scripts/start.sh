#!/bin/bash
exec statsd_exporter --statsd.listen-udp=0.0.0.0:8125 --log.level=debug

