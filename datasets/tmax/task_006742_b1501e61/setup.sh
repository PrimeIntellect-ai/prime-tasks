#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw_parts.csv
1,,Engine,5000.0
2,1,Piston,150.0
3,1,Cylinder,300.0
4,1,Valve,50.0
5,2,Piston Ring,10.0
6,2,Connecting Rod,80.0
7,,Chassis,2000.0
8,7,Frame,1500.0
9,7,Suspension,400.0
10,9,Shock Absorber,120.0
11,9,Spring,60.0
12,8,Bolts,5.0
13,,Dashboard,300.0
14,13,Display,250.0
15,13,Wiring,20.0
EOF

    chmod -R 777 /home/user
