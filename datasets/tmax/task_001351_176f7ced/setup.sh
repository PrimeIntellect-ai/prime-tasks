#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest

mkdir -p /home/user/libs
mkdir -p /home/user/data

# Create library source files
cat << 'EOF' > /home/user/libs/lib1.c
int process_value(int x) { return x + 10; }
EOF

cat << 'EOF' > /home/user/libs/lib2.c
int process_value(int x) { return x * 2; }
EOF

cat << 'EOF' > /home/user/libs/lib3.c
int process_value(int x) { return x * 100; }
EOF

# Compile shared libraries
gcc -shared -o /home/user/libs/libmathops-1.0.5.so -fPIC /home/user/libs/lib1.c
gcc -shared -o /home/user/libs/libmathops-1.4.2.so -fPIC /home/user/libs/lib2.c
gcc -shared -o /home/user/libs/libmathops-2.0.1.so -fPIC /home/user/libs/lib3.c
gcc -shared -o /home/user/libs/libmathops-1.4.11.so -fPIC /home/user/libs/lib3.c
gcc -shared -o /home/user/libs/libmathops-1.12.3.so -fPIC /home/user/libs/lib2.c

rm /home/user/libs/*.c

# Create requests.csv
cat << 'EOF' > /home/user/data/requests.csv
1600000000,10,5
1600000001,10,-2
1600000002,10,8
1600000003,10,12
1600000004,22,10
1600000005,22,0
1600000006,22,3
EOF

cat << 'EOF' > /tmp/expected_output.jsonl
{"uid": 10, "result": 10}
{"uid": 10, "result": 16}
{"uid": 22, "result": 20}
{"uid": 22, "result": 6}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
