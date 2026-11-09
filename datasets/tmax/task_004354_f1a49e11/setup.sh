#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip nginx
pip3 install pytest flask requests

mkdir -p /home/user/app
mkdir -p /home/user/corpus/clean /home/user/corpus/evil

cat << 'EOF' > /home/user/app/nginx.conf
events {}
http {
    server {
        listen 8080;
        location /api/ {
            # BROKEN: routes to itself causing loop
            proxy_pass http://127.0.0.1:8080/api/;
        }
    }
}
EOF

cat << 'EOF' > /home/user/app/core.py
from flask import Flask, request, jsonify
app = Flask(__name__)

@app.route('/api/patch', methods=['POST'])
def patch():
    return jsonify({"status": "success", "applied": True}), 200

if __name__ == '__main__':
    app.run(port=8082)
EOF

cat << 'EOF' > /home/user/app/start.sh
#!/bin/bash
nginx -c /home/user/app/nginx.conf &
python3 /home/user/app/core.py &
# python3 /home/user/app/sanitizer.py &
EOF
chmod +x /home/user/app/start.sh

cat << 'EOF' > /home/user/corpus/clean/1.json
[{"op": "replace", "path": "/name", "value": "Bob"}]
EOF

cat << 'EOF' > /home/user/corpus/clean/2.json
[{"op": "add", "path": "/preferences/theme", "value": "dark"}, {"op": "replace", "path": "/age", "value": 30}]
EOF

cat << 'EOF' > /home/user/corpus/clean/3.json
[{"op": "remove", "path": "/identities/0"}]
EOF

cat << 'EOF' > /home/user/corpus/evil/1.json
[{"op": "replace", "path": "/role", "value": "admin"}]
EOF

cat << 'EOF' > /home/user/corpus/evil/2.json
[{"op": "replace", "path": "/name", "value": "Bob"}, {"op": "add", "path": "/is_admin", "value": true}]
EOF

cat << 'EOF' > /home/user/corpus/evil/3.json
[{"op": "remove", "path": "/role/1"}]
EOF

cat << 'EOF' > /home/user/corpus/evil/4.json
[{"op": "replace", "path": "/id", "value": 9999}]
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
