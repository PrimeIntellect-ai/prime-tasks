#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git openssh-server iproute2 curl sudo
    pip3 install pytest flask

    useradd -m -s /bin/bash user || true

    mkdir -p /app/metrics_stack
    cat << 'EOF' > /app/metrics_stack/server.py
from flask import Flask, request
app = Flask(__name__)
@app.route('/push', methods=['POST'])
def push():
    return "OK"
if __name__ == '__main__':
    app.run(host='10.0.0.5', port=8080)
EOF

    cat << 'EOF' > /app/metrics_stack/start.sh
#!/bin/bash
ip link add metric0 type dummy 2>/dev/null || true
ip link set metric0 up 2>/dev/null || true
python3 /app/metrics_stack/server.py &
/usr/sbin/sshd -f /home/user/sshd_config
EOF
    chmod +x /app/metrics_stack/start.sh

    mkdir -p /home/user/.ssh
    ssh-keygen -t rsa -N "" -f /home/user/.ssh/id_rsa
    cp /home/user/.ssh/id_rsa.pub /home/user/.ssh/authorized_keys

    cat << 'EOF' > /home/user/sshd_config
Port 2222
ListenAddress 127.0.0.1
HostKey /etc/ssh/ssh_host_rsa_key
PubkeyAuthentication no
EOF

    ssh-keygen -A

    mkdir -p /home/user/git-server/repo.git
    git init --bare /home/user/git-server/repo.git

    # Mock ip command for the test environment since dummy interface can't persist in image
    mv /sbin/ip /sbin/ip.real
    cat << 'EOF' > /sbin/ip
#!/bin/bash
if [ "$1" == "link" ] && [ "$2" == "show" ] && [ "$3" == "metric0" ]; then
    echo "3: metric0: <BROADCAST,NOARP,UP,LOWER_UP> mtu 1500 qdisc noqueue state UNKNOWN mode DEFAULT group default qlen 1000"
    exit 0
fi
exec /sbin/ip.real "$@"
EOF
    chmod +x /sbin/ip

    chown -R user:user /home/user
    chmod -R 777 /home/user
