#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget gnupg2 software-properties-common lsb-release curl redis-server
    pip3 install pytest redis

    # Install OpenResty for Nginx with Lua support
    wget -O - https://openresty.org/package/pubkey.gpg | apt-key add -
    add-apt-repository -y "deb http://openresty.org/package/ubuntu $(lsb_release -sc) main"
    apt-get update
    apt-get install -y openresty

    # Create symlink for nginx
    ln -s /usr/local/openresty/nginx/sbin/nginx /usr/sbin/nginx

    # Create directories
    mkdir -p /app/bin
    mkdir -p /app/services/nginx
    mkdir -p /app/services/backend

    # Create obfuscated logger (using a wrapper script for simplicity and safety)
    cat << 'EOF' > /app/bin/obfuscated_logger
#!/bin/bash
python3 -c "import sys, hashlib; s=sys.argv[1]; m=hashlib.md5(s.encode()).hexdigest(); h=hashlib.sha256(m.encode()).hexdigest(); print(f'{s}||{h}')" "$1"
EOF
    chmod +x /app/bin/obfuscated_logger

    # Create broken nginx.conf
    cat << 'EOF' > /app/services/nginx/nginx.conf
worker_processes  1;
events {
    worker_connections  1024;
}
http {
    server {
        listen       8080;
        server_name  localhost;

        location /log {
            content_by_lua_block {
                local redis = require "resty.redis"
                local red = redis:new()
                red:set_timeouts(1000, 1000, 1000)
                -- BROKEN: wrong port
                local ok, err = red:connect("127.0.0.1", 6378)
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end
                ngx.req.read_body()
                local body = ngx.req.get_body_data()
                -- BROKEN: wrong list name
                local res, err = red:lpush("wrong_logs", body)
                if not res then
                    ngx.say("failed to push: ", err)
                    return
                end
                ngx.say("ok")
            }
        }
    }
}
EOF

    # Create broken backend worker
    cat << 'EOF' > /app/services/backend/worker.py
import redis
import time

def main():
    # BROKEN: wrong port
    r = redis.Redis(host='127.0.0.1', port=6378, decode_responses=True)
    while True:
        try:
            # BROKEN: wrong list name
            result = r.brpop('wrong_logs', timeout=1)
            if result:
                _, message = result
                with open('/home/user/verified_logs.txt', 'a') as f:
                    f.write(message + '\n')
        except Exception as e:
            time.sleep(1)

if __name__ == '__main__':
    main()
EOF

    # Create user
    useradd -m -s /bin/bash user || true

    # Set permissions
    chmod -R 777 /app
    chmod -R 777 /home/user
