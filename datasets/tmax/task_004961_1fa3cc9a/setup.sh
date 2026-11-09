#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server zlib1g-dev build-essential
    pip3 install pytest flask redis

    mkdir -p /home/user/uploads
    mkdir -p /home/user/verified_backups
    mkdir -p /home/user/config
    mkdir -p /home/user/sample_data
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    cat << 'EOF' > /home/user/config/upload_config.json
{
  "upload_dir": "/tmp/wrong_dir/"
}
EOF

    cat << 'EOF' > /home/user/config/stats_config.json
{
  "redis_port": 9999
}
EOF

    cat << 'EOF' > /home/user/config/filter_config.json
{
  "allowed_versions": [1, 2],
  "max_payload_size": 10485760
}
EOF

    cat << 'EOF' > /home/user/upload_api.py
import json
from flask import Flask, request
import os

app = Flask(__name__)
config = json.load(open('/home/user/config/upload_config.json'))

@app.route('/upload', methods=['POST'])
def upload():
    file = request.files['file']
    file.save(os.path.join(config['upload_dir'], file.filename))
    return "OK"

if __name__ == '__main__':
    app.run(port=8080)
EOF

    cat << 'EOF' > /home/user/stats_api.py
import json
from flask import Flask
import redis

app = Flask(__name__)
config = json.load(open('/home/user/config/stats_config.json'))
r = redis.Redis(port=config['redis_port'])

@app.route('/stats', methods=['GET'])
def stats():
    try:
        count = r.get('verified_backup_count')
        return {"verified_backup_count": int(count) if count else 0}
    except Exception as e:
        return {"error": str(e)}, 500

if __name__ == '__main__':
    app.run(port=8081)
EOF

    cat << 'EOF' > /home/user/start_services.sh
#!/bin/bash
redis-server --daemonize yes
python3 /home/user/upload_api.py &
python3 /home/user/stats_api.py &
EOF
    chmod +x /home/user/start_services.sh

    # Generate sample corpus files
    python3 -c "
import struct
import zlib
import os

def write_cbf(path, magic, version, flags, payload):
    with open(path, 'wb') as f:
        f.write(magic)
        f.write(struct.pack('<H', version))
        f.write(struct.pack('<H', flags))
        f.write(struct.pack('<I', len(payload)))
        f.write(payload)
        f.write(struct.pack('<I', zlib.crc32(payload) & 0xFFFFFFFF))

write_cbf('/app/corpus/clean/clean1.dat', b'BKUP', 1, 0, b'valid payload data')
write_cbf('/app/corpus/evil/evil1.dat', b'BAD!', 1, 0, b'evil payload data')
write_cbf('/app/corpus/evil/evil2.dat', b'BKUP', 3, 0, b'bad version data')
write_cbf('/home/user/sample_data/sample.dat', b'BKUP', 2, 0, b'sample data')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
