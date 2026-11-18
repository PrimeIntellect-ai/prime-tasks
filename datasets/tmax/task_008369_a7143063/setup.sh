#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/logs

    cat << 'EOF' > "/home/user/logs/app log 1.txt"
INFO: System started
ERROR: disk full
INFO: shutting down
EOF

    python3 -c '
with open("/home/user/logs/corrupt.log", "wb") as f:
    f.write(b"INFO: Request received\n")
    f.write(b"ERROR: " + b"\xff" + b" database corrupted\n")
    f.write(b"ERROR: timeout\n")
'

    cat << 'EOF' > /home/user/process_logs.sh
#!/bin/bash
echo 0 > /home/user/total_errors.txt
for f in $(ls /home/user/logs/); do
    python3 /home/user/process.py /home/user/logs/$f
done
EOF
    chmod +x /home/user/process_logs.sh

    cat << 'EOF' > /home/user/process.py
import sys

def main():
    filepath = sys.argv[1]
    count = 0
    with open(filepath, 'r') as f:
        for line in f:
            if "ERROR" in line:
                count += 1

    with open('/home/user/total_errors.txt', 'r') as tf:
        total = int(tf.read().strip())

    with open('/home/user/total_errors.txt', 'w') as tf:
        tf.write(str(total + count) + '\n')

if __name__ == '__main__':
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
