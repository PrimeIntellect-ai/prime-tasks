#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx socat curl procps
    pip3 install pytest

    mkdir -p /home/user/nginx/conf
    mkdir -p /home/user/nginx/logs
    mkdir -p /home/user/nginx/temp

    cat << 'EOF' > /home/user/nginx/conf/nginx.conf
worker_processes 1;
daemon off;
error_log /home/user/nginx/logs/error.log;
pid /home/user/nginx/logs/nginx.pid;

events {
    worker_connections 1024;
}

http {
    access_log /home/user/nginx/logs/access.log;
    client_body_temp_path /home/user/nginx/temp/client_body;
    proxy_temp_path /home/user/nginx/temp/proxy;
    fastcgi_temp_path /home/user/nginx/temp/fastcgi;
    uwsgi_temp_path /home/user/nginx/temp/uwsgi;
    scgi_temp_path /home/user/nginx/temp/scgi;

    server {
        listen 8080;
        server_name localhost;

        location / {
            proxy_pass http://unix:/tmp/backend.sock;
            proxy_set_header Host $host;
            proxy_set_header HTTP_USER_AGENT $http_user_agent;
        }
    }
}
EOF

    cat << 'EOF' > /home/user/app.sh
#!/bin/bash
read -r request_line
while read -r header; do
    header=$(echo "$header" | tr -d '\r')
    [ -z "$header" ] && break
    if [[ "$header" == HTTP_USER_AGENT:* ]]; then
        user_agent="${header#HTTP_USER_AGENT: }"
        if [[ "$user_agent" == *"BadBot"* ]]; then
            # FRAGILE: Crash on bad bot
            exit 1
        fi
    fi
done

echo -ne "HTTP/1.1 200 OK\r\n"
echo -ne "Content-Type: text/plain\r\n"
echo -ne "\r\n"
echo -ne "Hello from Bash Backend!\n"
EOF
    chmod +x /home/user/app.sh

    cat << 'EOF' > /home/user/daemon.sh
#!/bin/bash
rm -f /home/user/run/app.sock
exec socat UNIX-LISTEN:/home/user/run/app.sock,fork EXEC:/home/user/app.sh
EOF
    chmod +x /home/user/daemon.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
