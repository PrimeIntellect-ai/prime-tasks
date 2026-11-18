#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/evidence

    cat << 'EOF' > /home/user/evidence/index.html
<!DOCTYPE html>
<html>
<head>
    <title>Dashboard</title>
</head>
<body>
    <h1>System Status: OK</h1>
    <!-- PAYLOAD: MzEzMjMzMmUzMTM5MzIzZTMzMzQyZTM1MzY= -->
    <p>All services running.</p>
</body>
</html>
EOF

    cat << 'EOF' > /home/user/evidence/backup.sh
#!/bin/bash
# Nightly backup script
BACKUP_DIR=$1
if [ -z "$BACKUP_DIR" ]; then
  echo "Usage: $0 <dir>"
  exit 1
fi
# Vulnerable command execution
eval "tar -czf /tmp/backup.tar.gz $BACKUP_DIR"
echo "Backup complete."
EOF
    chmod +x /home/user/evidence/backup.sh

    cat << 'EOF' > /home/user/evidence/sshd_config_compromised
# Standard SSH config
Port 22
Protocol 2

# Authentication:
LoginGraceTime 2m
PermitRootLogin yes
StrictModes yes
MaxAuthTries 6
MaxSessions 10

# To disable tunneled clear text passwords, change to no here!
PasswordAuthentication yes
PermitEmptyPasswords yes

# Forwarding
X11Forwarding no
EOF

    chmod -R 777 /home/user
