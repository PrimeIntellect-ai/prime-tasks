#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/weights.txt
# W1 (Input to Hidden, 3x4 matrix. Row 1 corresponds to weights for x1 into the 4 hidden neurons)
0.1 -0.2 0.3 0.0
-0.1 0.5 0.0 0.2
0.0 0.0 -0.4 0.1
# b1 (Hidden layer biases, 1x4 vector)
0.1 -0.1 0.2 0.0
# W2 (Hidden to Output, 4x1 matrix)
0.5
-0.5
1.0
0.2
# b2 (Output layer bias, scalar)
-0.2
EOF

    cat << 'EOF' > /home/user/data.csv
id,v1,v2,v3
1,2.0,3.0,2.718281828
2,1.0,0.0,1.0
3,-1.0,2.0,7.389056099
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
