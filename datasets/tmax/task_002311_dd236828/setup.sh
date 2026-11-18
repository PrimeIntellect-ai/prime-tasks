#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip expect
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/auth.log
Jan 12 10:00:01 server [sshd] Accepted publickey for admin 10.0.0.2 port 50123 ssh2
Jan 12 10:05:22 server [sshd] Connection closed by authenticating user root 192.168.1.105 port 33412 [preauth]
Jan 12 10:06:10 server [sshd] Connection closed by authenticating user admin 10.0.0.5 port 12345 [preauth]
Jan 12 10:07:05 server [sshd] Connection closed by authenticating user root 192.168.1.105 port 33413 [preauth]
Jan 12 10:10:00 server [sshd] Connection closed by authenticating user test 172.16.0.4 port 44444 [preauth]
Jan 12 10:11:00 server [sshd] Connection closed by authenticating user test 172.16.0.4 port 44445 [preauth]
Jan 12 10:12:00 server [sshd] Connection closed by authenticating user test 172.16.0.4 port 44446 [preauth]
Jan 12 10:13:00 server [sshd] Connection closed by authenticating user test 172.16.0.4 port 44447 [preauth]
Jan 12 10:14:00 server [sshd] Connection closed by authenticating user test 172.16.0.4 port 44448 [preauth]
Jan 12 10:15:22 server [sshd] Connection closed by authenticating user root 192.168.1.105 port 33414 [preauth]
Jan 12 10:16:10 server [sshd] Connection closed by authenticating user admin 10.0.0.5 port 12346 [preauth]
Jan 12 10:17:05 server [sshd] Connection closed by authenticating user root 192.168.1.105 port 33415 [preauth]
EOF

    cat << 'EOF' > /home/user/deploy_fw
#!/bin/bash
echo -n "Target IP to block: "
read ip
echo -n "Select deployment stage (rolling/staged/all): "
read stage
echo -n "Confirm deployment (y/n): "
read confirm

if [ "$confirm" = "y" ]; then
    echo "SUCCESS: Blocked $ip in $stage environment" > /home/user/deployment_success.log
    echo "Deployment logged."
else
    echo "Aborted."
fi
EOF

    chmod +x /home/user/deploy_fw
    chmod -R 777 /home/user
