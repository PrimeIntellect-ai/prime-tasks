#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user/graph_db
    for i in $(seq 1 500); do
      echo "$i,$((i+1)),10"
      echo "$i,$((i+2)),15"
      if [ $((i*2)) -le 500 ]; then
        echo "$i,$((i*2)),50"
      fi
    done > /home/user/graph_db/edges.csv

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/graph_db
    chmod -R 777 /home/user
