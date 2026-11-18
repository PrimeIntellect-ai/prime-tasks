#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk tar gzip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_sensors

    echo "0.5,-0.2,1.5" > /home/user/model_weights.txt

    cat << 'EOF' > /home/user/raw_sensors/sensor_A.csv
id,f1,f2,f3
1,10.0,5.0,2.0
2,NA,-10.0,4.0
3,100.0,2.0,NA
4,-60.0,0.0,1.0
EOF

    cat << 'EOF' > /home/user/raw_sensors/sensor_B.csv
id,f1,f2,f3
5,0.0,NA,10.0
6,20.0,20.0,20.0
7,-10.0,80.0,5.0
8,NA,NA,NA
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
