#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/train_data.txt
ID|Sensor_A|Sensor_B|Target
1|2.5|10.0|7.45
2|-1.0|5.0|4.00
3|3.0|12.0|8.70
4|4.5|8.0|NaN
5|1.5|7.0|4.95
6|5.0|9.0|13.70
7|0.0|0.0|1.20
EOF

    cat << 'EOF' > /home/user/test_data.txt
ID|Sensor_A|Sensor_B|Target
8|2.0|1.0|6.20
9|4.0|2.0|11.20
10|-2.5|3.0|1.00
11|3.5|4.0|9.95
12|1.0|5.0|NaN
EOF

    chmod -R 777 /home/user
