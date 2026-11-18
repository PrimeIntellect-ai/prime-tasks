#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar
    pip3 install pytest

    mkdir -p /home/user/storage /home/user/cleaned_logs
    cd /home/user

    # Generate node1.log
    for i in $(seq 1 40); do echo "[INFO] some log message" >> node1.log; done
    for i in $(seq 1 30); do echo "[DEBUG] some log message" >> node1.log; done
    for i in $(seq 1 20); do echo "[TRACE] some log message" >> node1.log; done
    for i in $(seq 1 10); do echo "[ERROR] some log message" >> node1.log; done

    # Generate node2.log
    for i in $(seq 1 100); do echo "[INFO] some log message" >> node2.log; done
    for i in $(seq 1 50); do echo "[DEBUG] some log message" >> node2.log; done
    for i in $(seq 1 50); do echo "[ERROR] some log message" >> node2.log; done

    # Generate node3.log
    for i in $(seq 1 150); do echo "[TRACE] some log message" >> node3.log; done

    # Compress into tar.gz
    tar -czf node1.tar.gz node1.log
    tar -czf node2.tar.gz node2.log
    tar -czf node3.tar.gz node3.log

    # Create nested archive
    tar -cf storage/telemetry_logs.tar node1.tar.gz node2.tar.gz node3.tar.gz

    # Cleanup intermediate files
    rm node1.log node2.log node3.log node1.tar.gz node2.tar.gz node3.tar.gz

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
