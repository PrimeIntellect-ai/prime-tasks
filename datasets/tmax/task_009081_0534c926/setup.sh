#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make libc6-dev wget curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'CSV' > /home/user/metadata.csv
sensor_id,location,group
S1,North_Wing,A
S2,South_Wing,B
CSV

    cat << 'JSONL' > /home/user/telemetry.jsonl
{"ts": 1700000000, "sensor": "S1", "val": 12.5, "msg": "ok \u0041"}
{"ts": 1700000020, "sensor": "S1", "val": 15.0, "msg": "bad \uX9ZZ here"}
{"ts": 1700000040, "sensor": "S1", "val": 14.5, "msg": "end"}
{"ts": 1700000010, "sensor": "S2", "val": 8.0, "msg": "start"}
{"ts": 1700000020, "sensor": "S2", "val": 8.5, "msg": "mid \uG123"}
JSONL

    chmod -R 777 /home/user
