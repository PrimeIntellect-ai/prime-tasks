#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server curl
    pip3 install pytest flask redis gunicorn requests

    mkdir -p /home/user/corpus/evil /home/user/corpus/clean /home/user/nginx /home/user/app /home/user/nginx/logs /home/user/nginx/temp

    # Generate dummy clean files
    for i in $(seq 1 10); do
        cat <<EOF > "/home/user/corpus/clean/req_$i.txt"
POST /upload HTTP/1.1
Host: localhost:8080
Content-Type: application/octet-stream
Content-Length: 64

\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x3e\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00CLEAN_DATA_$i
EOF
    done

    # Generate dummy evil files (with fake anomalies)
    for i in $(seq 1 10); do
        cat <<EOF > "/home/user/corpus/evil/req_$i.txt"
POST /upload HTTP/1.1
Host: localhost:8080
Content-Type: application/octet-stream
Content-Length: 64

\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x3e\x00\x01\x00\x00\x00\xff\xff\xff\xff\xff\xff\xff\xffEVIL_SHELLCODE_L2Jpbi9zaA==_$i
EOF
    done

    # Create Flask app
    cat <<'EOF' > /home/user/app/app.py
from flask import Flask, request
app = Flask(__name__)

@app.route('/upload', methods=['POST'])
def upload():
    data = request.get_data()
    return "OK", 200

if __name__ == '__main__':
    app.run(port=5000)
EOF

    # Create Nginx config
    cat <<'EOF' > /home/user/nginx/nginx.conf
worker_processes 1;
daemon off;
error_log /home/user/nginx/logs/error.log;
pid /home/user/nginx/nginx.pid;

events {
    worker_connections 1024;
}

http {
    client_body_temp_path /home/user/nginx/temp/client_body;
    proxy_temp_path /home/user/nginx/temp/proxy;
    fastcgi_temp_path /home/user/nginx/temp/fastcgi;
    uwsgi_temp_path /home/user/nginx/temp/uwsgi;
    scgi_temp_path /home/user/nginx/temp/scgi;

    access_log /home/user/nginx/logs/access.log;

    server {
        listen 8080;
        server_name localhost;

        location / {
            proxy_pass http://127.0.0.1:5000;
        }
    }
}
EOF

    # Create start_services.sh
    cat <<'EOF' > /home/user/start_services.sh
#!/bin/bash
redis-server --daemonize yes
python3 /home/user/app/app.py &
nginx -c /home/user/nginx/nginx.conf &
sleep 2
EOF
    chmod +x /home/user/start_services.sh

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
