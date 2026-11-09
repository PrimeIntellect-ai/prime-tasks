#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx git curl
    pip3 install pytest flask

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/gateway
    mkdir -p /home/user/waf
    mkdir -p /app/corpus/evil
    mkdir -p /app/corpus/clean

    cat << 'EOF' > /home/user/gateway/nginx.conf
worker_processes 1;
pid /tmp/nginx.pid;
error_log /tmp/error.log;
events {
    worker_connections 1024;
}
http {
    client_body_temp_path /tmp/client_body;
    fastcgi_temp_path /tmp/fastcgi_temp;
    proxy_temp_path /tmp/proxy_temp;
    scgi_temp_path /tmp/scgi_temp;
    uwsgi_temp_path /tmp/uwsgi_temp;
    access_log /tmp/access.log;

    server {
        listen 8080;
        server_name localhost;

        location /telemetry {
            proxy_pass http://127.0.0.1:5000;
        }
    }
}
EOF

    cat << 'EOF' > /app/flask_api.py
from flask import Flask, request, jsonify
app = Flask(__name__)

@app.route('/telemetry', methods=['POST'])
def telemetry():
    return jsonify({"status": "recorded"}), 200

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
nginx -c /home/user/gateway/nginx.conf
nohup python3 /app/flask_api.py > /tmp/flask.log 2>&1 &
sleep 2
EOF
    chmod +x /app/start_services.sh

    cat << 'EOF' > /app/corpus/clean/clean1.json
{"device_id": "sensor-01A", "readings": {"temp": 25.4, "humidity": 60}}
EOF

    cat << 'EOF' > /app/corpus/evil/evil1.json
{"device_id": "drop table;", "readings": {}}
EOF

    cat << 'EOF' > /app/corpus/evil/evil2.json
{"device_id": "id1", "readings": {"temp": "NaN"}}
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
