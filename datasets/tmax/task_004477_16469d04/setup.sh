#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc bubblewrap nginx
    pip3 install pytest flask pyjwt

    mkdir -p /app/bin /app/backend /app/nginx
    useradd -m -s /bin/bash user || true

    # Create legacy C binary
    cat << 'EOF' > /app/bin/legacy_auth.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    char *secret = "SECRET_KEY_9988776655";
    if (argc < 2) {
        printf("{\"status\": \"error\", \"reason\": \"missing_token\"}\n");
        return 1;
    }
    printf("{\"status\": \"success\", \"token\": \"%s\"}\n", argv[1]);
    return 0;
}
EOF
    gcc /app/bin/legacy_auth.c -o /app/bin/legacy_auth
    chmod +x /app/bin/legacy_auth

    # Create backend app
    cat << 'EOF' > /app/backend/app.py
from flask import Flask
app = Flask(__name__)

@app.route('/api/data')
def data():
    return '{"data": "success"}'

if __name__ == '__main__':
    app.run(port=5000)
EOF

    # Create nginx configuration
    cat << 'EOF' > /app/nginx/nginx.conf
events {}
http {
    server {
        listen 8080;
        location /api/data {
            auth_request /auth;
            proxy_pass http://127.0.0.1:5000;
        }
        location = /auth {
            internal;
            proxy_pass http://127.0.0.1:8081;
        }
    }
}
EOF

    # Create startup script
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
nginx -c /app/nginx/nginx.conf &
python3 /app/backend/app.py &
/app/bin/legacy_auth &
wait
EOF
    chmod +x /app/start_services.sh

    chmod -R 777 /home/user
    chmod -R 777 /app
