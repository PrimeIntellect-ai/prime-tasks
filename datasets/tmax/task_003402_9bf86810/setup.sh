#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sudo wget curl postgresql-14
    pip3 install pytest flask

    # Install Go 1.21
    wget https://go.dev/dl/go1.21.0.linux-amd64.tar.gz
    tar -C /usr/local -xzf go1.21.0.linux-amd64.tar.gz
    rm go1.21.0.linux-amd64.tar.gz
    ln -s /usr/local/go/bin/go /usr/local/bin/go
    ln -s /usr/local/go/bin/gofmt /usr/local/bin/gofmt

    mkdir -p /app
    cat << 'SCRIPT_EOF' > /app/start_services.sh
#!/bin/bash
# Start postgres
su - postgres -c "/usr/lib/postgresql/14/bin/pg_ctl -D /var/lib/postgresql/14/main -l logfile start"
sleep 5
sudo -u postgres psql -c "ALTER USER postgres PASSWORD 'password';"
sudo -u postgres createdb etl_db

# Start python app
cat << 'EOF' > /app/app.py
from flask import Flask, jsonify
app = Flask(__name__)
@app.route('/bulk_data', methods=['GET'])
def data():
    return jsonify([
        {"sensor_id": 1, "timestamp": 1, "value": 10.0},
        {"sensor_id": 1, "timestamp": 2, "value": 10.0},
        {"sensor_id": 1, "timestamp": 3, "value": 100.0},
        {"sensor_id": 1, "timestamp": 4, "value": 12.0},
        {"sensor_id": 1, "timestamp": 5, "value": 200.0},
        {"sensor_id": 1, "timestamp": 6, "value": 20.0},
        {"sensor_id": 1, "timestamp": 8, "value": 5.0}
    ])
if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8081)
EOF
nohup python3 /app/app.py > /dev/null 2>&1 &
SCRIPT_EOF

    chmod +x /app/start_services.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
