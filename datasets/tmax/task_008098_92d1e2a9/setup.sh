#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip socat acl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/vm_sockets
    mkdir -p /home/user/bin

    cat << 'EOF' > /home/user/config.env
export VM_NAME="test-vm-01"
export UPSTREAM_SOCKET="/home/user/vm_sockets/vnc.sock"
export DOWNSTREAM_TARGET="/home/user/vm_sockets/vnc_target.sock"
EOF

    cat << 'EOF' > /home/user/deploy.sh
#!/bin/bash
source /home/user/config.env

echo "Starting mock QEMU VNC service..."
# Clean up old socket
rm -f "$UPSTREAM_SOCKET"

# Simulate QEMU process creating a VNC unix socket in the background
socat UNIX-LISTEN:"$UPSTREAM_SOCKET",fork,echo EXEC:"echo VNC_MOCK_RESPONSE" &
SOCAT_PID=$!

# Wait for socket creation
sleep 1

echo "Running downstream health-check..."
# The health check strictly checks if the group 'users' has ACL permissions on the directory
ACL_CHECK=$(getfacl /home/user/vm_sockets | grep "group:users:rwx")

if [ -z "$ACL_CHECK" ]; then
    echo "ERROR: Missing required ACL permissions for 'users' group on /home/user/vm_sockets/"
    kill $SOCAT_PID
    exit 1
fi

# Attempt to connect to the configured downstream target
RESPONSE=$(echo "PING" | socat - UNIX-CONNECT:"$DOWNSTREAM_TARGET" 2>/dev/null)

if [ "$RESPONSE" = "VNC_MOCK_RESPONSE" ]; then
    echo "Success! Connected to VNC socket."
    echo "VNC_HEALTH_CHECK_PASSED" > /home/user/deployment.log
else
    echo "ERROR: 502 Bad Gateway. Could not connect to upstream VNC socket at $DOWNSTREAM_TARGET."
    kill $SOCAT_PID
    exit 1
fi

kill $SOCAT_PID
exit 0
EOF

    chmod +x /home/user/deploy.sh
    chown -R user:user /home/user

    chmod -R 777 /home/user
    chmod 700 /home/user/vm_sockets
