#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip redis-server libssl-dev libarchive-dev libhiredis-dev build-essential
pip3 install pytest flask redis

mkdir -p /app
cat << 'EOF' > /app/validator.py
import os
import tarfile
import redis
import json
from flask import Flask, jsonify

app = Flask(__name__)

@app.route('/validate')
def validate():
    try:
        r = redis.Redis(host='127.0.0.1', port=6379, decode_responses=True)
        manifest_str = r.get('backup:manifest')
        if not manifest_str:
            return jsonify({"status": "error", "message": "No manifest in Redis"}), 400
        manifest = json.loads(manifest_str)

        if not os.path.exists('/home/user/backup.tar'):
            return jsonify({"status": "error", "message": "backup.tar not found"}), 400

        with tarfile.open('/home/user/backup.tar', 'r') as tar:
            members = tar.getnames()
            if len(members) != 10000:
                return jsonify({"status": "error", "message": "Not all files in tar"}), 400

        return jsonify({"status": "success"})
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8080)
EOF

useradd -m -s /bin/bash user || true
mkdir -p /home/user/raw_data

# Generate 10,000 files
python3 -c '
import os
for i in range(10000):
    with open(f"/home/user/raw_data/file_{i:04d}.dat", "wb") as f:
        f.write(os.urandom(1024))
'

cat << 'EOF' > /home/user/slow_backup.py
# Slow backup implementation stub
print("Running slow backup...")
EOF

chmod -R 777 /home/user
chmod -R 777 /app
