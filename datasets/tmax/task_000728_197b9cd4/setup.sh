#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip jq tar
    pip3 install pytest

    mkdir -p /home/user/raw_dataset/exp_a
    mkdir -p /home/user/raw_dataset/exp_b/nested
    mkdir -p /home/user/raw_dataset/loop_dir

    # 1. Create Symlink loops
    ln -s /home/user/raw_dataset/loop_dir/link2 /home/user/raw_dataset/loop_dir/link1
    ln -s /home/user/raw_dataset/loop_dir/link1 /home/user/raw_dataset/loop_dir/link2
    # valid link
    touch /home/user/raw_dataset/exp_a/real_file.txt
    ln -s /home/user/raw_dataset/exp_a/real_file.txt /home/user/raw_dataset/exp_a/valid_link.txt

    # 2. Create archives (valid and corrupt)
    # Valid zip
    echo "dummy data" > /tmp/dummy1.txt
    cd /tmp && zip /home/user/raw_dataset/exp_a/data.zip dummy1.txt
    # Corrupt zip
    echo "this is not a zip file" > /home/user/raw_dataset/exp_b/bad_data.zip
    # Valid tar.gz
    tar -czf /home/user/raw_dataset/exp_b/nested/archive.tar.gz dummy1.txt
    # Corrupt tar.gz
    echo "corrupt tar data" > /home/user/raw_dataset/exp_b/nested/broken.tar.gz

    # 3. Create JSON and CSV files
    cat << 'EOF' > /home/user/raw_dataset/exp_a/measurements.json
[
  {"id": 101, "value": "alpha"},
  {"id": 102, "value": "beta"}
]
EOF

    cat << 'EOF' > /home/user/raw_dataset/exp_b/nested/stats.json
[
  {"id": 999, "value": "omega"}
]
EOF

    cat << 'EOF' > /home/user/raw_dataset/exp_b/existing.csv
id,value
1,original
2,data
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/raw_dataset
    chmod -R 777 /home/user
