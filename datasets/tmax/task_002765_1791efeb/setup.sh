#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server curl psmisc
    pip3 install pytest flask redis python-dotenv

    mkdir -p /app/nginx /app/data/clean /app/data/evil

    cat << 'EOF' > /app/nginx/nginx.conf
events {}
http {
    server {
        listen 8080;
        location /ingest {
            # proxy_pass http://127.0.0.1:5000;
        }
    }
}
EOF

    cat << 'EOF' > /app/.env
REDIS_HOST=dead.external.server.local
REDIS_PORT=6379
EOF

    cat << 'EOF' > /app/api.py
import os
import subprocess
import redis
from flask import Flask, request, jsonify
from dotenv import load_dotenv

load_dotenv('/app/.env')

app = Flask(__name__)
r = redis.Redis(host=os.getenv('REDIS_HOST', '127.0.0.1'), port=int(os.getenv('REDIS_PORT', 6379)))

@app.route('/ingest', methods=['POST'])
def ingest():
    if 'file' not in request.files:
        return jsonify({"error": "No file part"}), 400
    file = request.files['file']
    if file.filename == '':
        return jsonify({"error": "No selected file"}), 400

    input_path = f"/tmp/{file.filename}"
    output_path = f"/tmp/out_{file.filename}"
    file.save(input_path)

    try:
        result = subprocess.run(
            ['python3', '/home/user/validate_loc.py', input_path, output_path],
            capture_output=True, text=True
        )
        if result.returncode == 0:
            try:
                r.incr('success_count')
            except:
                pass
            return jsonify({"status": "success"}), 200
        else:
            try:
                r.incr('error_count')
            except:
                pass
            return jsonify({"status": "rejected"}), 400
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    cat << 'EOF' > /app/restart_services.sh
#!/bin/bash
service nginx restart
service redis-server restart
pkill -f "python3 /app/api.py" || true
nohup python3 /app/api.py > /app/api.log 2>&1 &
sleep 2
EOF
    chmod +x /app/restart_services.sh

    cat << 'EOF' > /app/data/clean/clean_1.json
{"hello": "world", "goodbye": "farewell", "yes": "no"}
EOF

    cat << 'EOF' > /app/data/clean/clean_2.csv
key,translation
test,this is a test
apple,a fruit
EOF

    cat << 'EOF' > /app/data/evil/evil_1.csv
key,translation
normal,this is fine
bad,this is a massive string that will definitely skew the mean and standard deviation significantly because it is so extremely long compared to the other strings in this file
EOF

    cat << 'EOF' > /app/data/evil/evil_2.json
{"hello": "world", "bad": "<script>alert(1)</script>"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
