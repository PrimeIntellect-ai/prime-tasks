#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/model_outputs.csv
timestamp,sensor_id,raw_value,model_prediction
2023-01-01T00:00,A,10.0,10.1
2023-01-01T00:01,A,NaN,10.2
2023-01-01T00:02,B,12.0,11.0
2023-01-01T00:03,B,100.0,15.0
2023-01-01T00:04,A,,10.0
2023-01-01T00:05,C,11.0,10.8
2023-01-01T00:06,C,9.0,9.6
2023-01-01T00:07,A,10.5,10.5
2023-01-01T00:08,B,NULL,NULL
2023-01-01T00:09,A,11.5,12.1
2023-01-01T00:10,B,8.5,8.2
2023-01-01T00:11,C,9.5,10.0
2023-01-01T00:12,C,10.2,9.6
EOF

    chmod -R 777 /home/user
