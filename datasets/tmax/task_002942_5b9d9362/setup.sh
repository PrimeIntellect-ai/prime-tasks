#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl util-linux
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/intercepts
    mkdir -p /home/user/vuln_redacted

    # Generate certificates
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /home/user/intercepts/cert1.pem -out /home/user/intercepts/cert1.pem -subj "/CN=SecureCert1" 2>/dev/null
    openssl req -x509 -nodes -days 365 -newkey rsa:1024 -keyout /home/user/intercepts/cert2.pem -out /home/user/intercepts/cert2.pem -subj "/CN=WeakCert1" 2>/dev/null
    openssl req -x509 -nodes -days 365 -newkey rsa:4096 -keyout /home/user/intercepts/cert3.pem -out /home/user/intercepts/cert3.pem -subj "/CN=SecureCert2" 2>/dev/null
    openssl req -x509 -nodes -days 365 -newkey rsa:1024 -keyout /home/user/intercepts/cert4.pem -out /home/user/intercepts/cert4.pem -subj "/CN=WeakCert2" 2>/dev/null

    chown -R user:user /home/user/intercepts
    chown -R user:user /home/user/vuln_redacted

    chmod -R 777 /home/user
