#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gzip coreutils gawk sed grep
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_data
    mkdir -p /home/user/scripts
    mkdir -p /home/user/clean_data
    mkdir -p /home/user/processed_data/label_0
    mkdir -p /home/user/processed_data/label_1
    mkdir -p /home/user/metrics
    mkdir -p /home/user/cv_folds

    cat << 'EOF' > /home/user/setup_data.py
import random
random.seed(42)

def generate_data(num_files=3):
    for i in range(num_files):
        with open(f"/home/user/raw_data/file_{i}.csv", "w") as f:
            for j in range(1000):
                # 90% valid, 10% invalid
                if random.random() < 0.9:
                    id = random.randint(1, 10000)
                    ts = f"2023-10-12T10:{random.randint(10,59)}:{random.randint(10,59)}Z"
                    label = random.choice([0, 1])
                    if label == 0:
                        val = round(random.uniform(10.0, 50.0), 2)
                    else:
                        val = round(random.uniform(30.0, 80.0), 2)
                    f.write(f"{id},{ts},{val},{label}\n")
                else:
                    # Invalid cases
                    error_type = random.choice(["bad_id", "bad_ts", "bad_val", "bad_label"])
                    if error_type == "bad_id":
                        f.write(f"abc,2023-10-12T10:15:30Z,15.5,0\n")
                    elif error_type == "bad_ts":
                        f.write(f"123,2023/10/12 10:15:30,15.5,0\n")
                    elif error_type == "bad_val":
                        f.write(f"123,2023-10-12T10:15:30Z,NaN,0\n")
                    elif error_type == "bad_label":
                        f.write(f"123,2023-10-12T10:15:30Z,15.5,2\n")

generate_data()
EOF
    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    chmod -R 777 /home/user
