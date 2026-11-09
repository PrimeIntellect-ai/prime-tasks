#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl espeak ffmpeg build-essential
    pip3 install --default-timeout=100 pytest

    # Install Rust
    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/rust
    curl https://sh.rustup.rs -sSf | sh -s -- -y
    export PATH="/opt/rust/bin:$PATH"

    # Create directories
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Generate audio file
    espeak -w /app/k8s_policy.wav "Security policy update: Reject any Kubernetes manifest that requests the host network. Specifically, if the pod spec contains hostNetwork set to true, it must be blocked."

    # Generate clean corpus
    cat << 'EOF' > /app/corpora/clean/pod1.yaml
apiVersion: v1
kind: Pod
metadata:
  name: clean-pod
spec:
  containers:
  - name: nginx
    image: nginx
EOF

    cat << 'EOF' > /app/corpora/clean/deploy1.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: clean-deploy
spec:
  template:
    spec:
      containers:
      - name: nginx
        image: nginx
EOF

    # Generate evil corpus
    cat << 'EOF' > /app/corpora/evil/pod1.yaml
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

    cat << 'EOF' > /app/corpora/evil/deploy1.yaml
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

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
    chmod -R 777 /opt/rust
