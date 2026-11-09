#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server nginx gcc curl
    pip3 install pytest flask gunicorn

    mkdir -p /app

    # Create secret seed
    echo -n "s3cr3t_k3y_123!" > /app/secret_seed.txt

    # Create Flask app
    cat << 'EOF' > /app/app.py
from flask import Flask, request, render_template_string

app = Flask(__name__)

@app.route('/')
def index():
    return "Hello from Flask"

@app.route('/render')
def render():
    tmpl = request.args.get('tmpl', 'Empty')
    return render_template_string(tmpl)

if __name__ == '__main__':
    app.run(port=5000)
EOF

    # Create start_services.sh
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
gunicorn --chdir /app -w 4 -b 127.0.0.1:5000 app:app --daemon
EOF
    chmod +x /app/start_services.sh

    # Create nginx.conf skeleton
    cat << 'EOF' > /app/nginx.conf
worker_processes 1;
events { worker_connections 1024; }
http {
    # TODO: Configure TLS on 8443, proxy to Flask, and add CSP header
    server {
        listen 80;
    }
}
EOF

    # Create oracle C source
    cat << 'EOF' > /app/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    FILE *f = fopen("/app/secret_seed.txt", "r");
    if (!f) return 1;
    char seed[256];
    if (!fgets(seed, sizeof(seed), f)) return 1;
    fclose(f);
    int seed_len = strlen(seed);
    if (seed_len > 0 && seed[seed_len-1] == '\n') {
        seed[seed_len-1] = '\0';
        seed_len--;
    }

    char hex_in[2048];
    if (!fgets(hex_in, sizeof(hex_in), stdin)) return 0;
    int hex_len = strlen(hex_in);
    if (hex_len > 0 && hex_in[hex_len-1] == '\n') {
        hex_in[hex_len-1] = '\0';
        hex_len--;
    }

    int out_len = hex_len / 2;
    unsigned char *out = malloc(out_len);
    for (int i = 0; i < out_len; i++) {
        unsigned int byte;
        sscanf(hex_in + 2*i, "%2x", &byte);
        unsigned char a = byte ^ seed[i % seed_len];
        unsigned char b = ((a << 2) & 0xFF) | (a >> 6);
        out[i] = b;
    }

    for (int i = 0; i < out_len; i++) {
        printf("%02x", out[i]);
    }
    printf("\n");
    free(out);
    return 0;
}
EOF
    gcc -o /app/log_obfuscator_oracle /app/oracle.c
    strip /app/log_obfuscator_oracle
    rm /app/oracle.c
    chmod +x /app/log_obfuscator_oracle

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
