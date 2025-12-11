#!/bin/bash
dir=/appz/log/archive
if [[ ! -e $dir ]]; then
    mkdir $dir
elif [[ ! -d $dir ]]; then
    echo "$dir already exists " 1>&2
fi

