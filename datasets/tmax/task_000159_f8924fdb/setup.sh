#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc libsqlite3-dev
pip3 install --default-timeout=100 pytest

mkdir -p /home/user

cat << 'EOF' > /home/user/flights.csv
id,source,dest,airline,delay
1,JFK,LAX,SkyCorp,15
2,JFK,SFO,SkyCorp,0
3,ORD,ATL,Delta,10
4,LAX,ORD,SkyCorp,45
5,SFO,JFK,SkyCorp,120
6,ATL,JFK,SkyCorp,5
7,JFK,MIA,SkyCorp,25
8,MIA,LAX,SkyCorp,60
9,ORD,JFK,SkyCorp,35
10,LAX,JFK,SkyCorp,50
11,SFO,LAX,SkyCorp,80
12,ATL,ORD,SkyCorp,90
13,JFK,ATL,SkyCorp,10
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
