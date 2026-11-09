#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip netcat-openbsd
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/repo.git/hooks
    mkdir -p /home/user/app
    mkdir -p /home/user/mail

    cat << 'EOF' > /home/user/repo.git/hooks/post-receive
#!/bin/bash
read branch
echo "Triggering deploy for $branch"
# Mismatched socket path
echo "DEPLOY" | nc -N -U /home/user/app/upstream.sock
if [ $? -ne 0 ]; then
    echo "Alert: Deployment failed" >> /home/user/mail/alerts.log
fi
EOF

    cat << 'EOF' > /home/user/app/deploy_daemon.sh
#!/bin/bash
rm -f /home/user/upstream.sock
# Listen on unix socket. Read one message, log it.
# We use python to ensure standard unix socket server behavior without nc variant issues
python3 -c "
import socket, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind('/home/user/upstream.sock')
s.listen(1)
while True:
    conn, addr = s.accept()
    data = conn.recv(1024)
    if b'DEPLOY' in data:
        with open('/home/user/app/deploy.log', 'w') as f:
            f.write('DEPLOY_SUCCESS\n')
    conn.close()
"
EOF

    chmod -R 777 /home/user
    chmod -x /home/user/repo.git/hooks/post-receive
