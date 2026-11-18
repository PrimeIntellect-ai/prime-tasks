#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        gcc \
        make \
        socat \
        openssl \
        systemd \
        wget \
        tar

    pip3 install pytest

    mkdir -p /app
    cd /app
    wget https://pyyaml.org/download/libyaml/yaml-0.2.5.tar.gz
    tar -xzf yaml-0.2.5.tar.gz
    mv yaml-0.2.5 libyaml-0.2.5
    rm yaml-0.2.5.tar.gz

    # Perturb configure script
    sed -i 's/CFLAGS="-g -O2"/CFLAGS="-g -O2 -Werror=this-is-a-deliberate-typo"/' /app/libyaml-0.2.5/configure

    # Create corpora directories
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Populate clean corpus
    cat << 'EOF' > /app/corpora/clean/clean1.yaml
apiVersion: v1
kind: Pod
metadata:
  name: clean-pod
spec:
  containers:
  - name: nginx
    image: nginx
EOF

    cat << 'EOF' > /app/corpora/clean/clean2.yaml
apiVersion: v1
kind: Pod
metadata:
  name: clean-pod2
spec:
  hostNetwork: false
  containers:
  - name: nginx
    image: nginx
EOF

    # Populate evil corpus
    cat << 'EOF' > /app/corpora/evil/evil1.yaml
apiVersion: v1
kind: Pod
metadata:
  name: evil-pod
spec:
  hostNetwork: true
  containers:
  - name: nginx
    image: nginx
EOF

    cat << 'EOF' > /app/corpora/evil/evil2.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: evil-deploy
spec:
  template:
    spec:
      hostNetwork: true
      containers:
      - name: nginx
        image: nginx
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
