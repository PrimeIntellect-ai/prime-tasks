#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk sed grep coreutils
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create the weights file
    cat << 'EOF' > weights.txt
2.5
-1.2
3.8
EOF

    # Create the data file with missing values
    cat << 'EOF' > data.csv
id,f1,f2,f3
1,10,20,30
2,5,,10
3,,15,
4,0,0,0
5,2,3,4
6,,,
7,-5,10,-2
8,1,,1
9,10,10,10
10,,,-5
EOF

    # Create an initial broken etl.sh
    cat << 'EOF' > etl.sh
#!/bin/bash
# Broken pipeline: hardcoded weights, fails on empty fields, outputs floats
awk -F, 'NR>1 {print $1 "," ($2*2.5 + $3*-1.2 + $4*3.8)}' /home/user/data.csv > /home/user/output.csv
EOF

    chmod +x etl.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
