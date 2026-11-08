#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx curl
    pip3 install pytest flask gunicorn

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Create the Flask app
    cat << 'EOF' > /app/app.py
from flask import Flask, jsonify
app = Flask(__name__)

@app.route('/health')
def health():
    return jsonify(status="ok"), 200

if __name__ == '__main__':
    app.run()
EOF

    # Create Nginx config
    mkdir -p /home/user
    cat << 'EOF' > /home/user/nginx.conf
worker_processes 1;
daemon off;
events {
    worker_connections 1024;
}
http {
    server {
        listen 127.0.0.1:8080;
        location / {
            proxy_pass http://unix:/tmp/wrong_dashboard.sock;
        }
    }
}
EOF

    # Create startup script
    cat << 'EOF' > /app/start.sh
#!/bin/bash
gunicorn --bind unix:/tmp/cost_dashboard.sock --chdir /app app:app --daemon
nginx -c /home/user/nginx.conf &
EOF
    chmod +x /app/start.sh

    # Create corpus files
    cat << 'EOF' > /app/corpus/clean/req1.json
{
  "resources": [
    {"type": "compute", "size": "t2.micro", "monthly_cost": 10},
    {"type": "storage", "size": "100GB", "monthly_cost": 20}
  ]
}
EOF

    cat << 'EOF' > /app/corpus/clean/req2.json
{
  "resources": [
    {"type": "compute", "size": "m5.large", "monthly_cost": 100}
  ]
}
EOF

    cat << 'EOF' > /app/corpus/evil/req1.json
{
  "resources": [
    {"type": "compute", "size": "x1.large", "monthly_cost": 300}
  ]
}
EOF

    cat << 'EOF' > /app/corpus/evil/req2.json
{
  "resources": [
    {"type": "compute", "size": "t2.micro", "monthly_cost": 600}
  ]
}
EOF

    cat << 'EOF' > /app/corpus/evil/req3.json
{
  "resources": [
    {"type": "compute", "size": "p3.8xlarge", "monthly_cost": 400}
  ]
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
