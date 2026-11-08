#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip expect rustc cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/legacy_mailer.py
#!/usr/bin/env python3
import sys

def main():
    recipient = input("Recipient: ")
    subject = input("Subject: ")
    message = input("Message: ")
    confirm = input("Send? (y/n): ")

    if confirm.lower() == 'y':
        with open("/home/user/outbox.txt", "a") as f:
            f.write(f"TO: {recipient}\nSUBJECT: {subject}\nBODY: {message}\n---\n")
        print("Sent successfully.")
    else:
        print("Aborted.")

if __name__ == "__main__":
    main()
EOF
    chmod +x /home/user/legacy_mailer.py

    cat << 'EOF' > /home/user/test_system.log
[INFO] System started
[WARNING] Disk usage at 85%
[CRITICAL] Database connection lost
[INFO] Retrying connection
[CRITICAL] OOM Killer invoked
EOF

    chmod -R 777 /home/user
