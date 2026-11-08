#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak sqlite3
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Create the metadata database
    sqlite3 /app/metadata.db <<EOF
CREATE TABLE nodes (id INT, cluster_name TEXT, centrality_weight INT);
CREATE TABLE edges (source_id INT, target_id INT);

INSERT INTO nodes VALUES (1, 'cluster-A', 2);
INSERT INTO nodes VALUES (2, 'cluster-B', 3);
INSERT INTO nodes VALUES (3, 'cluster-C', 4);
INSERT INTO nodes VALUES (4, 'cluster-D', 4);

INSERT INTO edges VALUES (1, 4);
INSERT INTO edges VALUES (2, 4);
INSERT INTO edges VALUES (3, 4);

INSERT INTO edges VALUES (1, 2);
INSERT INTO edges VALUES (3, 2);
EOF

    # Create the audio file
    espeak -w /app/incident_report.wav "Listen closely. The attacker injected fake backup payloads. In a valid backup JSON, the 'validation_hash' field must exactly equal the total number of inbound graph edges for the 'cluster_id' specified in the JSON, multiplied by the node's 'centrality_weight' from the SQLite metadata database. If this cross-reference fails, the record is malicious."

    # Create clean corpus
    cat <<EOF > /app/corpus/clean/clean1.json
{
  "backup_id": "bkp-1",
  "cluster_id": 4,
  "validation_hash": 12
}
EOF

    cat <<EOF > /app/corpus/clean/clean2.json
{
  "backup_id": "bkp-2",
  "cluster_id": 2,
  "validation_hash": 6
}
EOF

    # Create evil corpus
    cat <<EOF > /app/corpus/evil/evil1.json
{
  "backup_id": "bkp-3",
  "cluster_id": 4,
  "validation_hash": 10
}
EOF

    cat <<EOF > /app/corpus/evil/evil2.json
{
  "backup_id": "bkp-4",
  "cluster_id": 2,
  "validation_hash": 5
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
