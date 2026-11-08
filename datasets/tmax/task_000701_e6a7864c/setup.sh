#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server gcc curl bash sudo
    pip3 install pytest flask redis

    # Create directories
    mkdir -p /app/nginx
    mkdir -p /app/flask
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Create Flask app
    cat << 'EOF' > /app/flask/app.py
from flask import Flask, request, redirect, make_response
import redis

app = Flask(__name__)
r = redis.Redis(host='127.0.0.1', port=6379, db=0)

@app.route('/auth')
def auth():
    next_url = request.args.get('next', '/')
    resp = make_response(redirect(next_url))
    resp.set_cookie('auth_token', 'dummy_token')
    return resp

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    # Create Nginx config (broken proxy_pass)
    cat << 'EOF' > /app/nginx/nginx.conf
events {}
http {
    server {
        listen 8080;

        location /auth {
            # proxy_pass missing here
        }
    }
}
EOF

    # Create start script
    cat << 'EOF' > /app/start.sh
#!/bin/bash
redis-server --daemonize yes
nginx -c /app/nginx/nginx.conf
python3 /app/flask/app.py &
EOF
    chmod +x /app/start.sh

    # Create C skeleton
    useradd -m -s /bin/bash user || true
    cat << 'EOF' > /home/user/token_validator.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const int b64index[256] = {
    0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
    0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
    0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  62, 63, 62, 62, 63,
    52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 0,  0,  0,  0,  0,  0,
    0,  0,  1,  2,  3,  4,  5,  6,  7,  8,  9,  10, 11, 12, 13, 14,
    15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 0,  0,  0,  0,  63,
    0,  26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40,
    41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51
};

unsigned char* base64_decode(const char* data, size_t input_length, size_t* output_length) {
    if (input_length % 4 != 0) return NULL;
    *output_length = input_length / 4 * 3;
    if (data[input_length - 1] == '=') (*output_length)--;
    if (data[input_length - 2] == '=') (*output_length)--;
    unsigned char* decoded_data = malloc(*output_length + 1);
    if (decoded_data == NULL) return NULL;
    for (size_t i = 0, j = 0; i < input_length;) {
        uint32_t a = data[i] == '=' ? 0 & i++ : b64index[(unsigned char)data[i++]];
        uint32_t b = data[i] == '=' ? 0 & i++ : b64index[(unsigned char)data[i++]];
        uint32_t c = data[i] == '=' ? 0 & i++ : b64index[(unsigned char)data[i++]];
        uint32_t d = data[i] == '=' ? 0 & i++ : b64index[(unsigned char)data[i++]];
        uint32_t triple = (a << 18) + (b << 12) + (c << 6) + d;
        if (j < *output_length) decoded_data[j++] = (triple >> 16) & 0xFF;
        if (j < *output_length) decoded_data[j++] = (triple >> 8) & 0xFF;
        if (j < *output_length) decoded_data[j++] = triple & 0xFF;
    }
    decoded_data[*output_length] = '\0';
    return decoded_data;
}

int main() {
    // Read from stdin and validate
    return 0;
}
EOF

    # Create corpora
    echo -n "user123|/dashboard|a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2" | base64 > /app/corpora/clean/1.txt
    echo -n "admin|/user/settings|1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef" | base64 > /app/corpora/clean/2.txt

    echo -n "user123|//evil.com|a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2" | base64 > /app/corpora/evil/1.txt
    echo -n "user123|http://attacker.com|a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2" | base64 > /app/corpora/evil/2.txt
    echo -n "user123|\/evil.com|a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2" | base64 > /app/corpora/evil/3.txt
    echo -n "user123|/dashboard|shortsig" | base64 > /app/corpora/evil/4.txt

    chmod -R 777 /home/user
    chmod -R 777 /app
