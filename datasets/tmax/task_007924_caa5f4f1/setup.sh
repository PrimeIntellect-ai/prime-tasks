#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required packages for the task
    apt-get install -y sqlite3 libsqlite3-dev gcc libc6-dev

    # Create user and home directory
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user
    cd /home/user

    # Create the SQLite database and populate it
    sqlite3 experiments.db <<EOF
CREATE TABLE raw_records (document TEXT);
INSERT INTO raw_records (document) VALUES ('{"experiment_id": "E1", "metadata": {"group": "Control", "timestamp": 100}, "results": {"primary_metric": 10.5}}');
INSERT INTO raw_records (document) VALUES ('{"experiment_id": "E2", "metadata": {"group": "Control", "timestamp": 105}, "results": {"primary_metric": 15.2}}');
INSERT INTO raw_records (document) VALUES ('{"experiment_id": "E3", "metadata": {"group": "Control", "timestamp": 110}, "results": {"primary_metric": 10.5}}');
INSERT INTO raw_records (document) VALUES ('{"experiment_id": "E4", "metadata": {"group": "Treatment", "timestamp": 101}, "results": {"primary_metric": 22.1}}');
INSERT INTO raw_records (document) VALUES ('{"experiment_id": "E5", "metadata": {"group": "Treatment", "timestamp": 102}, "results": {"primary_metric": 22.1}}');
INSERT INTO raw_records (document) VALUES ('{"experiment_id": "E6", "metadata": {"group": "Treatment", "timestamp": 103}, "results": {"primary_metric": 18.4}}');
EOF

    chmod 644 experiments.db

    # Set permissions
    chmod -R 777 /home/user
