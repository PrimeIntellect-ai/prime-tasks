#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc nginx curl
    pip3 install pytest flask requests

    mkdir -p /home/user/corpora/clean
    mkdir -p /home/user/corpora/evil

    # Clean corpus
    cat << 'EOF' > /home/user/corpora/clean/1.md
[link](safe.md)
EOF
    cat << 'EOF' > /home/user/corpora/clean/2.md
[link](dir/safe.md)
EOF
    cat << 'EOF' > /home/user/corpora/clean/3.md
[link](safe)
EOF
    cat << 'EOF' > /home/user/corpora/clean/4.md
[link](a/b/c.md)
EOF
    cat << 'EOF' > /home/user/corpora/clean/5.md
[link](test.png)
EOF

    # Evil corpus
    cat << 'EOF' > /home/user/corpora/evil/1.md
[link](/etc/passwd)
EOF
    cat << 'EOF' > /home/user/corpora/evil/2.md
[link](../safe.md)
EOF
    cat << 'EOF' > /home/user/corpora/evil/3.md
[link](a/../../b.md)
EOF
    cat << 'EOF' > /home/user/corpora/evil/4.md
[link](/absolute/path)
EOF
    cat << 'EOF' > /home/user/corpora/evil/5.md
[link](dir/../../../etc/shadow)
EOF

    mkdir -p /home/user/services/uploader
    mkdir -p /home/user/services/backup
    mkdir -p /home/user/services/nginx

    cat << 'EOF' > /home/user/services/uploader/config.json
{
  "FILTER_BIN": "",
  "PUBLISH_DIR": "",
  "BACKUP_URL": ""
}
EOF

    cat << 'EOF' > /home/user/services/uploader/app.py
from flask import Flask, request, jsonify
import os, subprocess, json, shutil

app = Flask(__name__)
with open('config.json') as f:
    config = json.load(f)

@app.route('/upload', methods=['POST'])
def upload():
    file = request.files['file']
    tmp_path = '/tmp/uploaded.md'
    file.save(tmp_path)

    res = subprocess.run([config['FILTER_BIN'], tmp_path])
    if res.returncode != 0:
        return "Rejected", 403

    pub_path = os.path.join(config['PUBLISH_DIR'], file.filename)
    shutil.move(tmp_path, pub_path)

    import requests
    try:
        requests.post(config['BACKUP_URL'], data="backup")
    except:
        pass

    return "Uploaded", 200

if __name__ == '__main__':
    app.run(port=5000)
EOF

    cat << 'EOF' > /home/user/services/backup/app.py
from flask import Flask
app = Flask(__name__)

@app.route('/backup', methods=['POST'])
def backup():
    return "Backed up", 200

if __name__ == '__main__':
    app.run(port=5001)
EOF

    cat << 'EOF' > /home/user/services/nginx/nginx.conf
events {}
http {
    server {
        listen 8080;
        location / {
            root /var/www/html;
        }
    }
}
EOF

    cat << 'EOF' > /home/user/services/start_all.sh
#!/bin/bash
cd /home/user/services/uploader && python3 app.py &
cd /home/user/services/backup && python3 app.py &
nginx -c /home/user/services/nginx/nginx.conf -g "daemon off;" &
wait
EOF
    chmod +x /home/user/services/start_all.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
