#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/research_data/raw

    python3 << 'EOF'
import os

raw_dir = "/home/user/research_data/raw"
os.makedirs(raw_dir, exist_ok=True)

last_run_time = 1600000000
with open("/home/user/last_run.txt", "w") as f:
    f.write(str(last_run_time))

def create_file(name, content, mtime):
    path = os.path.join(raw_dir, name)
    with open(path, "w") as f:
        f.write(content)
    os.utime(path, (mtime, mtime))

create_file("data1.csv", "id,reading\n1,50\n2,60\n", 1500000000)
create_file("data2.json", '{"readings": [10, 20, 30]}', 1650000000)
create_file("data3.xml", "<data><reading>150</reading><reading>200</reading></data>", 1650000000)
create_file("data4.csv", "id,reading\n1,10\n", 1500000000)
create_file("data5.json", '{"readings": [105]}', 1660000000)
EOF

    chmod -R 777 /home/user
