#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip nginx redis-server curl xxd
pip3 install pytest

mkdir -p /home/user/app/sanitizer-app/sanitizer
mkdir -p /home/user/app/sanitizer-app/tests
mkdir -p /home/user/app/legacy
mkdir -p /home/user/app/nginx
mkdir -p /home/user/data/evil
mkdir -p /home/user/data/clean

cat << 'EOF' > /home/user/app/legacy/detector.js
function decodeRecursively(text, depth=0) {
    if (depth > 5) return text;
    let decoded = text;
    try { decoded = decodeURIComponent(decoded); } catch(e) {}
    try { decoded = Buffer.from(decoded, 'base64').toString('utf-8'); } catch(e) {}
    try { 
        if (/^[0-9a-fA-F]+$/.test(decoded)) {
            decoded = Buffer.from(decoded, 'hex').toString('utf-8'); 
        }
    } catch(e) {}
    if (decoded !== text) return decodeRecursively(decoded, depth + 1);
    return decoded;
}
function isMalicious(text) {
    const dec = decodeRecursively(text);
    return dec.includes("<script>") || dec.includes("DROP TABLE") || dec.includes("evil_payload");
}
EOF

cat << 'EOF' > /home/user/app/sanitizer-app/pyproject.toml
[build-system]
requires = ["setuptools"]
build-backend = "setuptools.build_meta"

[project]
name = "sanitizer"
version = "0.1.0
dependencies = [
    "requests"
]
EOF

cat << 'EOF' > /home/user/app/nginx/nginx.conf
events {}
http {
    server {
        listen 8080;
        location /sanitize {
            proxy_pass http://127.0.0.1:9999;
        }
    }
}
EOF

cat << 'EOF' > /home/user/app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
nginx -c /home/user/app/nginx/nginx.conf
cd /home/user/app/sanitizer-app
export FLASK_APP=sanitizer.app
flask run --host=127.0.0.1 --port=5000 &
EOF
chmod +x /home/user/app/start_services.sh

touch /home/user/app/sanitizer-app/sanitizer/__init__.py
touch /home/user/app/sanitizer-app/tests/__init__.py

# Create evil corpus files
echo "PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==" | xxd -p | tr -d '\n' > /home/user/data/evil/1.txt
echo "DROP TABLE users;" | base64 > /home/user/data/evil/2.txt

# Create clean corpus files
echo "Hello world! Base64 is fun." > /home/user/data/clean/1.txt
echo "Just some normal text." > /home/user/data/clean/2.txt

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
