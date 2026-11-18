#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc socat netcat-openbsd curl
    pip3 install pytest flask

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Create 50 clean files
    for i in $(seq 1 50); do
        echo "{\"user\": \"john_$i\", \"id\": $i}" > /app/corpus/clean/file_$i.txt
    done

    # Create 50 evil files
    for i in $(seq 1 50); do
        if [ $((i % 4)) -eq 0 ]; then
            echo "SELECT * FROM users UNION SELECT 1,2,3" > /app/corpus/evil/file_$i.txt
        elif [ $((i % 4)) -eq 1 ]; then
            echo "{\"data\": \"admin' OR 1=1 --\"}" > /app/corpus/evil/file_$i.txt
        elif [ $((i % 4)) -eq 2 ]; then
            echo "<script>alert($i)</script>" > /app/corpus/evil/file_$i.txt
        else
            echo "DROP TABLE users;" > /app/corpus/evil/file_$i.txt
        fi
    done

    cat << 'EOF' > /app/backend.py
from flask import Flask, request, jsonify
app = Flask(__name__)
@app.route('/', defaults={'path': ''}, methods=['GET', 'POST', 'PUT', 'DELETE'])
@app.route('/<path:path>', methods=['GET', 'POST', 'PUT', 'DELETE'])
def catch_all(path):
    return jsonify({"status": "ok", "path": path})
if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8081)
EOF

    cat << 'EOF' > /app/audit.py
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.bind(('127.0.0.1', 8082))
s.listen(5)
while True:
    conn, addr = s.accept()
    data = conn.recv(4096)
    conn.close()
EOF

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
python3 /app/backend.py >/dev/null 2>&1 &
python3 /app/audit.py >/dev/null 2>&1 &
EOF
    chmod +x /app/start_services.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
