#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/workspace
    mkdir -p /home/user/mail/outbox

    cat << 'EOF' > /home/user/mda.sh
#!/bin/bash
trap "exit 0" SIGTERM
while true; do
    sleep 1
done
EOF
    chmod +x /home/user/mda.sh

    chown -R user:user /home/user/workspace
    chown -R user:user /home/user/mail
    chown user:user /home/user/mda.sh

    chmod -R 777 /home/user
