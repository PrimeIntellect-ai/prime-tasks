#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest aiosmtpd

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/app/mail_monitor.py
import os
import smtplib

def run_diagnostic():
    server_ip = os.environ['SMTP_SERVER_IP'] # Crashes if missing

    # Missing connection logic

    with open('report.log', 'a') as f: # Relative path
        f.write("Diagnostic run complete.\n")

if __name__ == "__main__":
    run_diagnostic()
EOF

    # Hijack pytest to start the SMTP server before running tests
    mv /usr/local/bin/pytest /usr/local/bin/pytest_real
    cat << 'EOF' > /usr/local/bin/pytest
#!/bin/bash
python3 -m aiosmtpd -n -l 127.0.0.1:10255 >/dev/null 2>&1 &
sleep 0.5
exec /usr/local/bin/pytest_real "$@"
EOF
    chmod +x /usr/local/bin/pytest

    # Also hijack bash to start it for the agent's interactive session if needed
    echo 'python3 -m aiosmtpd -n -l 127.0.0.1:10255 >/dev/null 2>&1 &' >> /home/user/.bashrc

    chmod -R 777 /home/user
