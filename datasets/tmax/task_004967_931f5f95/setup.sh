#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip netcat-openbsd
    pip3 install pytest

    mkdir -p /app/bash-csv-toolkit-1.2/
    cat << 'EOF' > /app/bash-csv-toolkit-1.2/filter_valid.sh
#!/bin/bash
if [ -z "$MIN_SCORE" ]; then
  MIN_SCORE=0
fi
awk -F"," -v MIN_SCOR="$MIN_SCORE" 'NR>1 && $3 >= 18 && $4 >= MIN_SCORE' "$1"
EOF
    chmod +x /app/bash-csv-toolkit-1.2/filter_valid.sh

    mkdir -p /home/user/data/
    cat << 'EOF' > /home/user/data/part_1.csv
id,name,age,score
1,Alice,20,60
2,Bob,17,80
3,Charlie,22,40
EOF

    cat << 'EOF' > /home/user/data/part_2.csv
id,name,age,score
4,David,25,90
5,Eve,30,50
6,Frank,16,100
EOF

    cat << 'EOF' > /home/user/data/part_3.csv
id,name,age,score
7,Grace,19,55
8,Heidi,21,45
9,Ivan,40,75
EOF

    cat << 'EOF' > /home/user/data/part_4.csv
id,name,age,score
10,Judy,18,50
11,Mallory,35,30
12,Niaj,28,85
EOF

    cat << 'EOF' > /home/user/data/part_5.csv
id,name,age,score
13,Oscar,23,65
14,Peggy,15,95
15,Sybil,50,55
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
