#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/generate_csv.py
import random

random.seed(42)
timestamps = ["1699999999", "1700000000", "1700000001"]
keys = [f"KEY_{i:02d}" for i in range(20)]
values = ["A", "B", "C", "D"]

with open("/home/user/config_stream.csv", "w") as f:
    for ts in timestamps:
        for s_idx in range(1, 101):
            server_id = f"server_{s_idx:03d}"

            # Base config for server_001
            if server_id == "server_001":
                random.seed(int(ts))
                my_config = {k: random.choice(values) for k in keys}
            elif server_id == "server_077" and ts == "1700000000":
                # Make server_077 very similar to server_001 at target timestamp
                random.seed(int(ts))
                my_config = {k: random.choice(values) for k in keys}
                # Change exactly 2 keys
                my_config["KEY_05"] = "X"
                my_config["KEY_12"] = "Y"
            else:
                my_config = {k: random.choice(values) for k in keys}

            for k, v in my_config.items():
                f.write(f"{ts},{server_id},{k},{v}\n")

EOF
python3 /tmp/generate_csv.py

chmod -R 777 /home/user
