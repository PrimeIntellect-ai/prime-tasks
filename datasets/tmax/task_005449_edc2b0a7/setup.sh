#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak nginx curl
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Generate audio file
    espeak -w /app/admin_note.wav "Hey, it's admin. To stop the database crashes, your classifier needs to reject any request that meets either of these two conditions. First, if the User-Agent header contains the word 'sqlmap' exactly. Second, if the body of the request contains the word 'DROP' or the phrase 'UNION SELECT', in any combination of upper or lower case. All other requests are perfectly fine and should be allowed through."

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/nginx/client_body /home/user/nginx/proxy /home/user/nginx/fastcgi /home/user/nginx/uwsgi /home/user/nginx/scgi

    cat << 'EOF' > /home/user/nginx/nginx.conf
worker_processes 1;
pid /home/user/nginx/nginx.pid;
error_log /home/user/nginx/error.log;
events {
    worker_connections 1024;
}
http {
    access_log /home/user/nginx/access.log;
    client_body_temp_path /home/user/nginx/client_body;
    proxy_temp_path /home/user/nginx/proxy;
    fastcgi_temp_path /home/user/nginx/fastcgi;
    uwsgi_temp_path /home/user/nginx/uwsgi;
    scgi_temp_path /home/user/nginx/scgi;

    server {
        listen 127.0.0.1:9090;
        location / {
            proxy_pass http://127.0.0.1:8081;
        }
    }
}
EOF

    # Create corpus files
    for i in $(seq 1 20); do
        cat << EOF > /app/corpus/clean/req_$i.txt
GET /page$i HTTP/1.1
Host: localhost
User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64)
Accept: */*

EOF
    done

    for i in $(seq 1 10); do
        cat << EOF > /app/corpus/evil/req_ua_$i.txt
GET /page$i HTTP/1.1
Host: localhost
User-Agent: sqlmap/1.5.8#dev
Accept: */*

EOF
    done

    for i in $(seq 1 10); do
        cat << EOF > /app/corpus/evil/req_body_$i.txt
POST /api/data HTTP/1.1
Host: localhost
User-Agent: curl/7.68.0
Content-Length: 20

SELECT * UNION SELECT 1,2,3
EOF
    done

    # Add a DROP example
    cat << EOF > /app/corpus/evil/req_body_drop.txt
POST /api/data HTTP/1.1
Host: localhost
User-Agent: curl/7.68.0
Content-Length: 20

; dRoP table users;
EOF

    chmod -R 777 /home/user
    chmod -R 777 /app
