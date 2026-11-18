#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git netcat-openbsd socat expect bash
    pip3 install pytest

    mkdir -p /home/user/bin
    mkdir -p /home/user/deploy-stage

    # 1. Create the interactive mock tool
    cat << 'EOF' > /home/user/bin/approve-manifests
#!/bin/bash
read -p "Enter operator password: " pass
if [ "$pass" != "k8s-ops-secret" ]; then
    echo "Access denied."
    exit 1
fi
read -p "Confirm deployment (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Deployment aborted."
    exit 1
fi
echo "Manifests approved."
exit 0
EOF
    chmod +x /home/user/bin/approve-manifests

    # 2. Create the mock validator daemon
    cat << 'EOF' > /home/user/bin/validator-daemon.sh
#!/bin/bash
# Simulate startup delay
sleep 3
# Start a simple listener on 8080
nc -l -p 8080 -k >/dev/null 2>&1 &
echo $! > /tmp/validator.pid
wait
EOF
    chmod +x /home/user/bin/validator-daemon.sh

    # 3. Create the mock applier
    cat << 'EOF' > /home/user/bin/applier.sh
#!/bin/bash
STAGE_DIR=$1
if ! nc -z 127.0.0.1 8080; then
    echo "ERROR: Validator daemon not running on 8080. Dependency missing."
    exit 1
fi

if ! nc -z 127.0.0.1 10025; then
    echo "ERROR: Notification port 10025 unreachable."
    exit 1
fi

# Simulate applying manifests and log success
echo "Successfully applied manifests from $STAGE_DIR" > /home/user/deploy-stage/applied.log
echo "Mock email sent" | nc 127.0.0.1 10025 -q 0 >/dev/null 2>&1
exit 0
EOF
    chmod +x /home/user/bin/applier.sh

    # 4. Initialize the bare git repository
    git init --bare /home/user/manifests.git

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
