#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_data.csv
1,45.5,alpha,1
-5,20.0,beta,0
2,105.0,gamma,1
3,0.0,delta,0
4,50.0,toolongcategory,1
5,25.5,,0
6,99.9,zeta,2
7,10.0,eta,1
8,notafloat,theta,0
9,55.5,iota,0
10,100.0,kappa,1
EOF
    chmod 644 /home/user/raw_data.csv

    chmod -R 777 /home/user
