#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip software-properties-common curl wget
    pip3 install pytest

    # Install Apptainer, Git, SSH, Socat, Expect
    add-apt-repository -y ppa:apptainer/ppa
    apt-get update && apt-get install -y apptainer git openssh-server openssh-client socat expect

    useradd -m -s /bin/bash user || true

    # Setup SSH Keys
    mkdir -p /home/user/.ssh
    ssh-keygen -t rsa -N "" -f /home/user/.ssh/id_rsa
    cat /home/user/.ssh/id_rsa.pub >> /home/user/.ssh/authorized_keys

    # Setup SSHD
    mkdir -p /run/sshd
    ssh-keygen -A

    # Setup Mock Service
    cat << 'EOF' > /home/user/mock_service.sh
#!/bin/bash
read -p "Login: " user
if [ "$user" != "planner" ]; then
    echo "Invalid user"
    exit 1
fi
read -p "Password: " pass
if [ "$pass" != "metrics_pass_99" ]; then
    echo "Invalid password"
    exit 1
fi
echo '{"status": "ok", "cpu_usage": 74.5, "mem_usage": 82.1, "nodes_active": 42}'
EOF
    chmod +x /home/user/mock_service.sh

    # Auto-start services on container exec
    cat << 'EOF' > /.singularity.d/env/99-services.sh
#!/bin/bash
if ! pgrep -x "sshd" > /dev/null; then
    /usr/sbin/sshd
fi
if ! pgrep -x "socat" > /dev/null; then
    nohup socat TCP-LISTEN:8888,reuseaddr,fork EXEC:"/home/user/mock_service.sh,pty,echo=0" > /dev/null 2>&1 &
fi
EOF
    chmod +x /.singularity.d/env/99-services.sh

    # Set permissions
    chmod -R 777 /home/user

    # Fix SSH permissions (strict requirements)
    chown -R user:user /home/user/.ssh
    chmod 700 /home/user/.ssh
    chmod 600 /home/user/.ssh/id_rsa
    chmod 600 /home/user/.ssh/authorized_keys
    chmod 644 /home/user/.ssh/id_rsa.pub
