#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/service_logs/web
    mkdir -p /home/user/service_logs/db
    mkdir -p /home/user/service_logs/cache
    mkdir -p /home/user/monitor_repo

    for i in $(seq 1 85); do echo "[INFO] Web request successful" >> /home/user/service_logs/web/app.log; done
    for i in $(seq 1 10); do echo "[ERROR] Web request failed" >> /home/user/service_logs/web/app.log; done
    for i in $(seq 1 5); do echo "[TIMEOUT] Connection dropped" >> /home/user/service_logs/web/app.log; done

    for i in $(seq 1 40); do echo "[INFO] Query OK" >> /home/user/service_logs/db/app.log; done
    for i in $(seq 1 10); do echo "[ERROR] Deadlock detected" >> /home/user/service_logs/db/app.log; done

    for i in $(seq 1 195); do echo "[INFO] Cache hit" >> /home/user/service_logs/cache/app.log; done
    for i in $(seq 1 5); do echo "[TIMEOUT] Redis node unreachable" >> /home/user/service_logs/cache/app.log; done

    chown -R user:user /home/user/service_logs
    chown -R user:user /home/user/monitor_repo

    chmod -R 777 /home/user
