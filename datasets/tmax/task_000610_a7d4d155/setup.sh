#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ curl netcat-openbsd gawk coreutils
    pip3 install pytest

    mkdir -p /app/server_data/data
    mkdir -p /app/data/clean
    mkdir -p /app/data/evil

    cat << 'EOF' > /app/generate_data.py
import os

def make_valid_row():
    return "1a2b3c4d,123,45.67,1650000000,true\n"

# Clean corpus
for i in range(10):
    with open(f'/app/data/clean/file{i}.csv', 'w') as f:
        for _ in range(5):
            f.write(make_valid_row())

# Evil corpus
evils = [
    "1a2b3c4,123,45.67,1650000000,true\n",
    "1a2b3c4dz,123,45.67,1650000000,true\n",
    "1a2b3c4d,0,45.67,1650000000,true\n",
    "1a2b3c4d,1000,45.67,1650000000,true\n",
    "1a2b3c4d,123,-50.1,1650000000,true\n",
    "1a2b3c4d,123,150.1,1650000000,true\n",
    "1a2b3c4d,123,45.67,1599999999,true\n",
    "1a2b3c4d,123,45.67,1700000001,true\n",
    "1a2b3c4d,123,45.67,1650000000,True\n",
    "1a2b3c4d,123,45.67,1650000000,FALSE\n",
]
for i, row in enumerate(evils):
    with open(f'/app/data/evil/file{i}.csv', 'w') as f:
        f.write(make_valid_row())
        f.write(row)

# Server data
files_list = []
for i in range(5):
    fname = f"valid_{i}.csv"
    with open(f'/app/server_data/data/{fname}', 'w') as f:
        for _ in range(3):
            f.write(make_valid_row())
    files_list.append(fname)

for i in range(5):
    fname = f"invalid_{i}.csv"
    with open(f'/app/server_data/data/{fname}', 'w') as f:
        f.write(make_valid_row())
        f.write(evils[i])
    files_list.append(fname)

with open('/app/server_data/files.list', 'w') as f:
    f.write('\n'.join(files_list) + '\n')
EOF

    python3 /app/generate_data.py

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
cd /app/server_data && python3 -m http.server 8080 &

cat << 'PYEOF' > /app/tcp_server.py
import socket
with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(('127.0.0.1', 9090))
    s.listen()
    while True:
        conn, addr = s.accept()
        with conn:
            data = conn.recv(1024)
            if data:
                with open('/app/accumulator_output.log', 'a') as f:
                    f.write(data.decode('utf-8'))
PYEOF

python3 /app/tcp_server.py &
EOF

    chmod +x /app/start_services.sh
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
