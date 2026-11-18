#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip nlohmann-json3-dev netcat-openbsd g++
pip3 install pytest

mkdir -p /app/corpus/clean /app/corpus/evil /app/services

cat << 'EOF' > /app/corpus/clean/data.jsonl
{"id": "A1", "sensor": "temp", "value": 22.5, "meta": "station_1"}
EOF

cat << 'EOF' > /app/corpus/evil/data.jsonl
{"id": "A2", "sensor": "temp", "value": 999.0, "meta": "station_1"}
{"id": "A3", "sensor": "temp", "value": 20.0, "meta": "drop table;"}
EOF

cat << 'EOF' > /app/services/source.py
import socket, time
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('127.0.0.1', 9001))
s.listen(5)
while True:
    try:
        conn, addr = s.accept()
        with open('/app/corpus/clean/data.jsonl', 'rb') as f:
            conn.sendall(f.read())
        conn.close()
    except:
        pass
EOF

cat << 'EOF' > /app/services/sink.py
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('127.0.0.1', 9002))
s.listen(5)
while True:
    try:
        conn, addr = s.accept()
        data = conn.recv(4096)
        if data:
            with open('/tmp/sink_output.log', 'ab') as f:
                f.write(data)
        conn.close()
    except:
        pass
EOF

cat << 'EOF' > /app/services/start.sh
#!/bin/bash
python3 /app/services/source.py &
python3 /app/services/sink.py &
EOF
chmod +x /app/services/start.sh

# Wrap pytest to ensure background services are running during tests
mv /usr/local/bin/pytest /usr/local/bin/pytest-real
cat << 'EOF' > /usr/local/bin/pytest
#!/bin/bash
/app/services/start.sh
sleep 1
/usr/local/bin/pytest-real "$@"
EOF
chmod +x /usr/local/bin/pytest

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user /app
