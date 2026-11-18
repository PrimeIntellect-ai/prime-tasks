#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_data.csv
user_id,age,annual_income,profession
1,25,50000,Engineer
2,45,120000,Doctor
3,30,40000,Artist
4,55,70000,Teacher
5,17,30000,Engineer
6,40,-5000,Doctor
7,35,80000,Hacker
8,150,90000,Teacher
9,28,60000,Engineer
10,50,110000,Doctor
11,,50000,Artist
12,42,85000,Teacher
13,33,65000,Engineer
14,38,105000,Doctor
15,29,45000,Artist
16,48,72000,Teacher
17,26,55000,Engineer
18,44,115000,Doctor
19,31,42000,Artist
20,52,68000,Teacher
21,27,58000,Engineer
22,46,125000,Doctor
23,32,48000,Artist
24,54,75000,Teacher
25,24,49000,Engineer
26,43,110000,Doctor
EOF

    cat << 'EOF' > /home/user/new_batch.csv
user_id,age,annual_income,profession
101,26,52000,Engineer
102,45,122000,Doctor
103,30,41000,Artist
104,95,1000000,Engineer
105,28,58000,Teacher
106,18,500000,Doctor
EOF

    chmod -R 777 /home/user
