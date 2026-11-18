#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/research_data/DS_001
    mkdir -p /home/user/research_data/DS_002
    mkdir -p /home/user/research_data/DS_003
    mkdir -p /home/user/raw_storage

    # Create log file
    cat << 'EOF' > /home/user/dataset_updates.log
[2023-10-01 10:00:00]
Dataset: DS_001
Status: SUCCESS
Details: Initial load.

[2023-10-01 10:05:00]
Dataset: DS_002
Status: FAILED
Details: Corrupted metadata.

[2023-10-02 11:00:00]
Dataset: DS_003
Status: SUCCESS
Details: Incremental update applied.
EOF

    # Create data files
    cat << 'EOF' > /home/user/research_data/DS_001/data.json
[
  {"id": 101, "measurement": 42.5, "sensor": "alpha"},
  {"id": 102, "measurement": 43.1, "sensor": "alpha"}
]
EOF

    cat << 'EOF' > /home/user/raw_storage/ds003_data.xml
<dataset>
  <record>
    <id>301</id>
    <measurement>99.9</measurement>
    <sensor>beta</sensor>
  </record>
  <record>
    <id>302</id>
    <measurement>100.1</measurement>
    <sensor>beta</sensor>
  </record>
</dataset>
EOF

    # Create symlinks
    ln -s /home/user/raw_storage/ds003_data.xml /home/user/research_data/DS_003/data.xml
    ln -s /home/user/research_data/DS_001 /home/user/research_data/DS_001/loop_dir
    ln -s /home/user/research_data/DS_003 /home/user/research_data/DS_003/loop_dir

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
