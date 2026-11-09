#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip redis-server redis-tools nginx curl jq
pip3 install pytest flask

mkdir -p /app/services
mkdir -p /app/corpus/clean
mkdir -p /app/corpus/evil
mkdir -p /app/logs

# Create Redis config
cat << 'EOF' > /app/services/redis.conf
port 6379
daemonize yes
logfile /app/logs/redis.log
dir /app/services/
EOF

# Create Flask API
cat << 'EOF' > /app/services/api.py
from flask import Flask, jsonify
app = Flask(__name__)

@app.route('/vector')
def vector():
    return jsonify({"v_x": 0.5, "v_y": -0.5, "v_z": 1.0})

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

# Create Nginx broken config
cat << 'EOF' > /app/services/nginx.conf
events {}
http {
    server {
        listen 8080;
        location /api/ {
            # BROKEN: missing proxy_pass or pointing to wrong port
            proxy_pass http://127.0.0.1:9999/;
        }
    }
}
EOF

# Create start script
cat << 'EOF' > /app/services/start.sh
#!/bin/bash
redis-server /app/services/redis.conf
nohup python3 /app/services/api.py > /app/logs/api.log 2>&1 &
nginx -c /app/services/nginx.conf -g "daemon on;"
EOF
chmod +x /app/services/start.sh

# Generate Corpus
# Clean files (dot product <= 10.0)
cat << 'EOF' > /app/corpus/clean/data1.csv
1,10.0,0.0,5.0
2,-5.0,5.0,2.5
EOF

cat << 'EOF' > /app/corpus/clean/data2.csv
3,0.0,0.0,0.0
4,2.0,2.0,2.0
EOF

# Evil files (dot product > 10.0)
cat << 'EOF' > /app/corpus/evil/anomaly1.csv
5,10.0,0.0,6.0
6,0.0,0.0,0.0
EOF

cat << 'EOF' > /app/corpus/evil/anomaly2.csv
7,0.0,-21.0,0.0
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user /app
