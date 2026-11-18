#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user/pipeline
cd /home/user/pipeline

cat << 'EOF' > parser.py
import sys

def process_logs():
    for line in sys.stdin:
        line = line.strip()
        remain = line
        while "<data>" in remain:
            start = remain.find("<data>") + 6
            end = remain.find("</data>", start)
            if end != -1:
                print(remain[start:end])
                remain = remain[end+7:]
            else:
                # BUG: Infinite loop because 'remain' is never modified when closing tag is missing
                pass

if __name__ == "__main__":
    process_logs()
EOF
chmod +x parser.py

cat << 'EOF' > run.sh
#!/bin/bash
cat "$1" | python3 parser.py
EOF
chmod +x run.sh

python3 -c '
import random
with open("large_input.txt", "w") as f:
    for i in range(1, 5001):
        if i == 3742:
            f.write(f"2023-10-14 10:22:14 [WARN] Connection timeout <data>partial_payload_missing_closing_tag\n")
        else:
            has_data = random.choice([True, False])
            if has_data:
                f.write(f"2023-10-14 10:22:14 [INFO] Processed job {i} <data>payload_{i}</data>\n")
            else:
                f.write(f"2023-10-14 10:22:14 [DEBUG] Heartbeat check {i}\n")
'

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
