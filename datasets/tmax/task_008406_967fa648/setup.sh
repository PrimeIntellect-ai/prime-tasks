#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc tar coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/dataset_temp/run_A
    mkdir -p /home/user/dataset_temp/run_B
    mkdir -p /home/user/dataset_temp/run_C/nested

    # Create infinite symlink loop
    ln -s ../../run_A /home/user/dataset_temp/run_C/nested/loop_link
    ln -s ../run_C /home/user/dataset_temp/run_A/loop_link2

    # Create log files
    cat << 'EOF' > /home/user/dataset_temp/run_A/exp1.log
BEGIN RECORD
Experiment: EXP-001
Status: FAILED
Result: 0.0
END RECORD
BEGIN RECORD
Experiment: EXP-002
Status: SUCCESS
Result: 99.1
END RECORD
EOF

    cat << 'EOF' > /home/user/dataset_temp/run_B/exp2.log
BEGIN RECORD
Experiment: EXP-003
Status: SUCCESS
Result: 45.2
END RECORD
BEGIN RECORD
Experiment: EXP-004
Status: SUCCESS
Result: 12.8
END RECORD
EOF

    cat << 'EOF' > /home/user/dataset_temp/run_C/nested/exp3.log
BEGIN RECORD
Experiment: EXP-005
Status: FAILED
Result: 88.8
END RECORD
EOF

    # Create some dummy files that should be ignored
    echo "Just some random notes" > /home/user/dataset_temp/run_B/notes.txt

    # Archive and split
    cd /home/user/dataset_temp
    tar -czf ../dataset.tar.gz .
    cd /home/user

    mkdir -p /home/user/raw_data
    split -b 150 /home/user/dataset.tar.gz /home/user/raw_data/dataset.tar.gz.part

    # Cleanup the original files to force the agent to reassemble and extract
    rm -rf /home/user/dataset_temp
    rm /home/user/dataset.tar.gz

    chmod -R 777 /home/user
