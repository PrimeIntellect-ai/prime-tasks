#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip make jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/etl_pipeline

    cat << 'EOF' > /home/user/etl_pipeline/source_A.csv
id,lat,lon
A1,40.7128,-74.0060
A2,34.0522,-118.2437
A3,41.8781,-87.6298
A4,48.8566,2.3522
EOF

    cat << 'EOF' > /home/user/etl_pipeline/source_B.json
[
  {"loc_id": "B1", "coordinates": {"latitude": 40.7306, "longitude": -73.9866}},
  {"loc_id": "B2", "coordinates": {"latitude": 34.0500, "longitude": -118.2500}},
  {"loc_id": "B3", "coordinates": {"latitude": 51.5074, "longitude": -0.1278}},
  {"loc_id": "B4", "coordinates": {"latitude": 48.8584, "longitude": 2.3508}}
]
EOF

    chown -R user:user /home/user/etl_pipeline
    chmod -R 777 /home/user
