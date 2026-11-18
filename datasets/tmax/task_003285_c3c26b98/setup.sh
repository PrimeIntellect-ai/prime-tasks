#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/graph_export.json
{
  "nodes": [
    {"id": 101, "label": "Cluster"},
    {"id": 102, "label": "Snapshot"},
    {"id": 103, "label": "Volume"},
    {"id": 104, "label": "Cluster"}
  ],
  "edges": [
    {"source": 101, "target": 103, "type": "MOUNTS"},
    {"source": 103, "target": 102, "type": "BACKED_BY"},
    {"source": 101, "target": 102, "type": "HAS_SNAPSHOT"},
    {"source": 104, "target": 103, "type": "MOUNTS"}
  ]
}
EOF

    cat << 'EOF' > /home/user/db_error.log
[2023-10-27 10:00:01] ERROR: Deadlock detected between Transaction 841 and Transaction 842.
[2023-10-27 10:00:01] TX 841 Query: MATCH (v:Volume)-[r:BACKED_BY]->(s:Snapshot) WHERE v.id = 103 SET r.status = 'verified'
[2023-10-27 10:00:01] TX 842 Query: MATCH (s:Snapshot)<-[r:BACKED_BY]-(v:Volume) WHERE s.id = 102 SET r.last_check = timestamp()
[2023-10-27 10:00:01] ACTION: Rolled back TX 842.
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
