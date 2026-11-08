#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/backup_metadata.jsonl
{"_id": "bkp_f1", "bkp_type": "full", "size_in_mb": 1500, "depends_on": null}
{"_id": "bkp_i1_1", "bkp_type": "incremental", "size_in_mb": 200, "depends_on": "bkp_f1"}
{"_id": "bkp_i1_2", "bkp_type": "incremental", "size_in_mb": 150, "depends_on": "bkp_i1_1"}
{"_id": "bkp_i1_3", "bkp_type": "incremental", "size_in_mb": 50, "depends_on": "bkp_i1_2"}
{"_id": "bkp_f2", "bkp_type": "full", "size_in_mb": 3000, "depends_on": null}
{"_id": "bkp_i2_1", "bkp_type": "incremental", "size_in_mb": 500, "depends_on": "bkp_f2"}
{"_id": "bkp_f3", "bkp_type": "full", "size_in_mb": 800, "depends_on": null}
{"_id": "bkp_i3_1", "bkp_type": "incremental", "size_in_mb": 100, "depends_on": "bkp_f3"}
{"_id": "bkp_i3_2", "bkp_type": "incremental", "size_in_mb": 100, "depends_on": "bkp_f3"}
{"_id": "bkp_i3_3", "bkp_type": "incremental", "size_in_mb": 150, "depends_on": "bkp_i3_1"}
EOF

    chmod -R 777 /home/user
