#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bash coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/manifests /home/user/network

    cat << 'EOF' > /home/user/manifests/app.conf
VM_NAME=backend
HOST_PORT=9090
VM_PORT=3000
EOF

    cat << 'EOF' > /home/user/vm-operator.sh
#!/bin/bash
# Flawed VM Operator
for f in /home/user/manifests/*.conf; do
  source "$f"
  qemu-system-x86_64 -m 256 -name $VM_NAME -netdev user,id=net0,hostfwd=tcp:127.0.0.1:$HOST_PORT-:$VM_PORT -device e1000,netdev=net0
done
EOF
    chmod +x /home/user/vm-operator.sh

    chmod -R 777 /home/user
