#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc git
    pip3 install pytest

    # Create the legacy transformer binary
    mkdir -p /app
    cat << 'EOF' > /tmp/transformer.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    char buffer[4096];
    if (!fgets(buffer, sizeof(buffer), stdin)) return 0;
    buffer[strcspn(buffer, "\r\n")] = 0;

    printf("{");
    char *pair = strtok(buffer, "|");
    int first = 1;
    while (pair) {
        char *colon = strchr(pair, ':');
        if (colon) {
            *colon = 0;
            char *key = pair;
            char *value = colon + 1;
            if (strlen(value) > 0) {
                if (!first) printf(", ");
                printf("\"%s\": \"%s\"", key, value);
                first = 0;
            }
        }
        pair = strtok(NULL, "|");
    }
    printf("}");
    return 0;
}
EOF
    gcc -O2 /tmp/transformer.c -o /app/legacy_transformer
    strip /app/legacy_transformer
    rm /tmp/transformer.c

    # Setup the git repository
    mkdir -p /home/user/ticket_repo
    cd /home/user/ticket_repo
    git init
    git config user.email "dev@example.com"
    git config user.name "Dev"

    cat << 'EOF' > requirements.txt
Flask==1.1.2
Werkzeug==2.0.0
EOF

    cat << 'EOF' > app.py
import os
import json
from flask import Flask, request, Response

if os.environ.get("APP_ENV") != "production":
    raise RuntimeError("APP_ENV must be production")

app = Flask(__name__)

def transform(data):
    result = {}
    if not data: return result
    pairs = data.split('|')
    for pair in pairs:
        if ':' in pair:
            key, val = pair.split(':', 1)
            if val:
                result[key] = val
    return result

@app.route('/transform', methods=['POST'])
def handle_transform():
    data = request.get_data(as_text=True)
    # Output compact JSON without extra spaces to match legacy
    return Response(json.dumps(transform(data), separators=(',', ':')), mimetype='application/json')

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8080)
EOF

    git add requirements.txt app.py
    git commit -m "Initial commit: working transformer"

    # Introduce the regression
    cat << 'EOF' > app.py
import os
import json
from flask import Flask, request, Response

if os.environ.get("APP_ENV") != "production":
    raise RuntimeError("APP_ENV must be production")

app = Flask(__name__)

def transform(data):
    result = {}
    if not data: return result
    pairs = data.split('|')
    for pair in pairs:
        if ':' in pair:
            key, val = pair.split(':', 1)
            result[key] = val
    return result

@app.route('/transform', methods=['POST'])
def handle_transform():
    data = request.get_data(as_text=True)
    return Response(json.dumps(transform(data), separators=(', ', ': ')), mimetype='application/json')

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8080)
EOF
    git add app.py
    git commit -m "Refactor transform logic"

    echo "# minor update" >> app.py
    git add app.py
    git commit -m "Minor update"

    echo "# another minor update" >> app.py
    git add app.py
    git commit -m "Another minor update"

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
