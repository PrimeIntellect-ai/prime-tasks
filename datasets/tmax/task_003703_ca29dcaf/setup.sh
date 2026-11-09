#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/mock_ssh
#!/bin/bash
if [ "$1" != "jumpuser@jumphost" ]; then
    echo "Usage: mock_ssh jumpuser@jumphost"
    exit 1
fi
echo "Attempting public key authentication..."
sleep 0.2
echo "Public key rejected. Fallback to password."
echo -n "password: "
read -r pass
if [ "$pass" = "probe_pass" ]; then
    echo "Access granted."
    exit 0
else
    echo "Access denied."
    exit 1
fi
EOF
    chmod +x /home/user/mock_ssh

    chmod -R 777 /home/user
