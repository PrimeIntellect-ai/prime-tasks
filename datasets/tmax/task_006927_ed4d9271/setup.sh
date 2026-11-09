#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_ratings.csv
user_id,item_id,rating
U1,I1,5.0
U1,I2,4.0
U1,I3,4.5
U1,I4,
U2,I1,4.0
U2,I2,4.0
U2,I3,5.0
U3,I1,1.0
U3,I2,2.0
U3,I4,1.5
U3,I5,1.0
U4,I1,5.0
U4,I2,3.5
U5,I1,4.5
U5,I2,4.5
U5,I3,5.0
U6,I4,4.0
U6,I5,5.0
U6,I6,4.5
U7,I4,4.5
U7,I5,4.0
U7,I6,5.0
U8,I1,
U8,I2,1.0
U9,I1,4.0
U9,I2,4.5
U9,I3,4.0
EOF

    chmod -R 777 /home/user
