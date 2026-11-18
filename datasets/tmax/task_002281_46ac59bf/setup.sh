#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++
pip3 install pytest

mkdir -p /home/user/inputs
mkdir -p /home/user/output

cat << 'EOF' > /home/user/inputs/batch1.csv
msg_id,lang,translation,timestamp,score
1,En_us,Hello,1620000000,85
2,fr_FR,Bonjour,1620000010,90
1,en_US,Hello!,1620000020,88
3,es_es,Hola,1620000030,92
4,En_us,Welcome,1620000040,80
5,en_US,Goodbye,1620000025,82
EOF

cat << 'EOF' > /home/user/inputs/batch2.csv
msg_id,lang,translation,timestamp,score
2,fr_fr,Salut,1620000050,95
5,en_US,Goodbye!,1620000060,89
3,es_ES,Hola!,1620000035,93
6,en_US,Thanks,1620000070,91
7,en_US,Yes,1620000080,85
4,en_US,Welcome!,1620000015,75
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
