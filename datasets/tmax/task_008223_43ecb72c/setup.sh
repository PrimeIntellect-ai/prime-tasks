#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest numpy pandas

mkdir -p /home/user/data /home/user/model

cat << 'EOF' > /home/user/model/weights.json
{
  "W1": [
    [0.5, -0.2, 0.1, 0.0],
    [0.1, 0.8, -0.5, 0.2],
    [-0.3, 0.0, 0.4, 0.9]
  ],
  "b1": [0.1, -0.1, 0.0, 0.2],
  "W2": [
    [0.4],
    [-0.5],
    [0.6],
    [0.1]
  ],
  "b2": [-0.2]
}
EOF

cat << 'EOF' > /home/user/data/sensor_A.csv
feature1,feature2,feature3
0.5,0.2,-0.1
-1.0,0.5,0.8
0.0,0.0,0.0
2.0,-1.5,0.3
EOF

cat << 'EOF' > /home/user/data/sensor_B.csv
feature1,feature2,feature3
1.5,1.2,1.1
-0.5,-0.2,-0.1
3.0,0.5,0.0
EOF

cat << 'EOF' > /home/user/data/sensor_C.csv
feature1,feature2,feature3
-2.0,-2.0,-2.0
0.1,0.2,0.3
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
