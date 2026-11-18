#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk sed grep
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/sensor_stream.log
2023-10-01 10:00:00 | INFO | IP: 192.168.1.10 | MSG: [temp=45] [humidity=60] [status=ok]
2023-10-01 10:05:00 | INFO | IP: 10.0.0.256 | MSG: [temp=20] [humidity=50] [status=ok]
2023-10-01 10:10:00 | INFO | IP: 172.16.5.5 | MSG: [temp=85] [humidity=40] [status=warn]
2023-10-01 10:15:00 | ERROR | IP: 192.168.1.12 | MSG: [temp=160] [humidity=90] [status=fail]
2023-10-01 10:20:00 | INFO | IP: 10.0.0.5 | MSG: [status=warn] [temp=30] [humidity=95]
2023-10-01 10:25:00 | INFO | IP: 192.168.1.10 | MSG: [humidity=60] [status=ok]
2023-10-01 10:30:00 | INFO | IP: 8.8.8.8 | MSG: [temp=-10] [humidity=20] [status=ok]
2023-10-01 10:35:00 | DEBUG | IP: 192.168.1.300 | MSG: [temp=10] [humidity=105]
2023-10-01 10:40:00 | INFO | IP: 127.0.0.1 | MSG: [temp=0] [humidity=0]
EOF

    chmod -R 777 /home/user
