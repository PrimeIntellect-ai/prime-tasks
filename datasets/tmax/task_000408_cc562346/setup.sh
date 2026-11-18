#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest pexpect

    mkdir -p /home/user/source_code

    cat << 'EOF' > /home/user/source_code/firmware.json
{"version": "2.1.0", "build": "stable", "features": ["wifi", "ble"]}
EOF

    cat << 'EOF' > /home/user/edge_vm.py
import sys
import time

def main():
    sys.stdout.write("Booting edge device...\n")
    sys.stdout.write("login: ")
    sys.stdout.flush()
    user = sys.stdin.readline().strip()

    sys.stdout.write("password: ")
    sys.stdout.flush()
    pwd = sys.stdin.readline().strip()

    if user != "admin" or pwd != "edge_secure_99":
        sys.stdout.write("Auth failed\n")
        sys.exit(1)

    sys.stdout.write("Device> ")
    sys.stdout.flush()
    cmd = sys.stdin.readline().strip()

    if cmd == "update":
        sys.stdout.write("Ready for payload: ")
        sys.stdout.flush()
        payload = sys.stdin.readline().strip()
        if "version" in payload:
            with open("/home/user/device_update.log", "w") as f:
                f.write(payload)
            sys.stdout.write("Update SUCCESS\n")
            sys.stdout.flush()
        else:
            sys.stdout.write("Update FAILED\n")
            sys.stdout.flush()
    else:
        sys.stdout.write("Unknown command\n")
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF

    cat << 'EOF' > /home/user/mock_smtp.py
import smtpd
import asyncore

class CustomSMTPServer(smtpd.SMTPServer):
    def process_message(self, peer, mailfrom, rcpttos, data, **kwargs):
        with open("/home/user/email_outbox.log", "a") as f:
            f.write(f"From: {mailfrom}\nTo: {rcpttos}\nData:\n{data.decode('utf-8')}\n---\n")

server = CustomSMTPServer(('127.0.0.1', 1025), None)
asyncore.loop()
EOF

    # Start the SMTP server automatically when the container runs
    cat << 'EOF' > /.singularity.d/env/99-smtp.sh
#!/bin/sh
python3 /home/user/mock_smtp.py >/dev/null 2>&1 &
EOF
    chmod +x /.singularity.d/env/99-smtp.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
