#!/bin/bash
sudo du -s /home/appz/volumes/* | sort -n -r | awk '{ s = $1 / 1024 / 1024 ; printf "%4.3f %s\n", s, $2 }' | grep -v "0.000"
