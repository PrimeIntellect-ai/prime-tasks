#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip iputils-ping
    pip3 install pytest

    mkdir -p /home/user/k8s-operator/manifests
    mkdir -p /home/user/k8s-operator/quarantine
    mkdir -p /home/user/k8s-operator/alerts

    cat << 'EOF' > /home/user/k8s-operator/manifests/app-good.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: good-ingress
spec:
  rules:
  host: 1.1.1.1
EOF

    cat << 'EOF' > /home/user/k8s-operator/manifests/app-bad.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: bad-ingress
spec:
  rules:
  host: definitely.invalid.domain.local.999
EOF

    echo "ALERT_TRIGGERED=0" > /home/user/k8s-operator/mail_config.rc

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/k8s-operator
    chmod -R 777 /home/user
