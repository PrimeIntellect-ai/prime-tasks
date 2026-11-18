#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip python3-venv
pip3 install pytest

mkdir -p /home/user/log_pipeline/data
cd /home/user/log_pipeline

cat << 'EOF' > requirements.txt
urllib3==1.26.15
requests==2.31.0
chardet==3.0.4
EOF

cat << 'EOF' > process_logs.py
import threading
import json
import glob
import collections
import os

error_counts = collections.defaultdict(int)

def process_file(filepath):
    try:
        with open(filepath, 'r') as f:
            for line in f:
                try:
                    data = json.loads(line)
                    if data.get("status", 200) >= 500:
                        # Race condition here
                        error_counts[data["ip"]] += 1
                except Exception:
                    pass
    except Exception as e:
        print(f"Error reading {filepath}: {e}")

def main():
    files = glob.glob('/home/user/log_pipeline/data/*.log')
    threads = []
    for f in files:
        t = threading.Thread(target=process_file, args=(f,))
        threads.append(t)
        t.start()

    for t in threads:
        t.join()

    with open('/home/user/log_pipeline/output.json', 'w') as f:
        json.dump(error_counts, f)

if __name__ == "__main__":
    main()
EOF

cat << 'EOF' > run.sh
#!/bin/bash
cd /home/user/log_pipeline
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python process_logs.py
EOF
chmod +x run.sh

cat << 'EOF' > generate_data.py
import json
import random

ips = [f"192.168.1.{i}" for i in range(1, 21)]
anomalous_ip = "10.0.42.17"

for file_idx in range(50):
    lines = []
    for _ in range(1000):
        if random.random() < 0.1:
            # Anomalous IP
            lines.append(json.dumps({"ip": anomalous_ip, "status": 500}))
        else:
            ip = random.choice(ips)
            status = 200 if random.random() < 0.9 else 503
            lines.append(json.dumps({"ip": ip, "status": status}))

    # File 25 will be utf-16 encoded
    encoding = 'utf-16' if file_idx == 25 else 'utf-8'
    with open(f"/home/user/log_pipeline/data/log_{file_idx}.log", "w", encoding=encoding) as f:
        for line in lines:
            f.write(line + "\n")
EOF
python3 generate_data.py
rm generate_data.py

useradd -m -s /bin/bash user || true
chown -R user:user /home/user/log_pipeline
chmod -R 777 /home/user
