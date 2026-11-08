#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pexpect

    mkdir -p /home/user/app
    cat << 'EOF' > /home/user/app/worker.py
import sys

def main():
    sys.stderr.write("Passkey: ")
    sys.stderr.flush()
    key = sys.stdin.readline().strip()
    if key == "DEPLOY_V2_READY":
        print("Worker updated successfully.")
    else:
        print("Invalid passkey.")
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF

    cat << 'EOF' > /home/user/app/deploy.sh
#!/bin/bash
python3 worker.py > deploy.log
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod 644 /home/user/app/deploy.sh
