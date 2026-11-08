#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev gcc make nginx curl
    pip3 install pytest flask

    mkdir -p /home/user/workspace/c_eval
    mkdir -p /home/user/workspace/proxy
    mkdir -p /app

    # Create Database files
    cat << 'EOF' > /home/user/workspace/v2_schema.sql
CREATE TABLE audit_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    expression TEXT,
    result INTEGER,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
);
EOF

    cat << 'EOF' > /home/user/workspace/migrate.sh
#!/bin/bash
sqlite3 data.db < v2_schema.sql
EOF
    chmod +x /home/user/workspace/migrate.sh

    # Create C Evaluator files
    cat << 'EOF' > /home/user/workspace/c_eval/Makefile
all: eval

eval: eval.c
	gcc -o eval eval.c
EOF

    cat << 'EOF' > /home/user/workspace/c_eval/eval.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <sqlite3.h>
#include <math.h>

void log_to_db(const char* expr, int res) {
    sqlite3 *db;
    char *err_msg = 0;
    int rc = sqlite3_open("../data.db", &db);
    if (rc != SQLITE_OK) return;
    char sql[256];
    sprintf(sql, "INSERT INTO audit_log (expression, result) VALUES ('%s', %d);", expr, res);
    sqlite3_exec(db, sql, 0, 0, &err_msg);
    sqlite3_close(db);
}

int main() {
    int server_fd, new_socket;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);
    char buffer[1024] = {0};

    server_fd = socket(AF_INET, SOCK_STREAM, 0);
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt));

    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(5002);

    bind(server_fd, (struct sockaddr *)&address, sizeof(address));
    listen(server_fd, 3);

    while(1) {
        new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen);
        read(new_socket, buffer, 1024);
        int v1, v2; char op[10]; sscanf(buffer, "%d %d %s", &v1, &v2, op);
        float float_val = 0;
        if (strcmp(op, "add") == 0) float_val = v1 + v2;
        else if (strcmp(op, "sub") == 0) float_val = v1 - v2;
        else if (strcmp(op, "mul") == 0) float_val = v1 * v2;
        int res = float_val;
        log_to_db(buffer, res);
        char res_str[256]; sprintf(res_str, "%d", res);
        send(new_socket, res_str, strlen(res_str), 0);
        close(new_socket);
    }
    return 0;
}
EOF

    # Create Proxy files
    cat << 'EOF' > /home/user/workspace/proxy/app.py
from flask import Flask, request
import socket

app = Flask(__name__)

@app.route('/compute')
def compute():
    v1 = request.args.get('v1')
    v2 = request.args.get('v2')
    op = request.args.get('op')

    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.connect(('127.0.0.1', 5002))
    s.sendall(f"{v1} {v2} {op}".encode())
    res = s.recv(1024).decode()
    s.close()
    return res

if __name__ == '__main__':
    app.run(port=5001)
EOF

    # Create Nginx config
    cat << 'EOF' > /home/user/workspace/nginx.conf
events {}
http {
    server {
        listen 8080;
        location /compute {
            proxy_pass http://127.0.0.1:9999;
        }
    }
}
EOF

    # Create Oracle process for fuzzer
    cat << 'EOF' > /app/oracle_process
#!/bin/bash
QUERY=$1
val1=$(echo "$QUERY" | grep -o 'val1=[^&]*' | cut -d= -f2)
val2=$(echo "$QUERY" | grep -o 'val2=[^&]*' | cut -d= -f2)
op=$(echo "$QUERY" | grep -o 'op=[^&]*' | cut -d= -f2)

if [ "$op" == "add" ]; then
    res=$((val1 + val2))
elif [ "$op" == "sub" ]; then
    res=$((val1 - val2))
elif [ "$op" == "mul" ]; then
    res=$((val1 * val2))
fi

echo "RESULT: $res"
EOF
    chmod +x /app/oracle_process

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
