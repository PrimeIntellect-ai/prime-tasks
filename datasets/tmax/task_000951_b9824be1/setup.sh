#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make libjson-c-dev
    pip3 install pytest flask requests

    mkdir -p /app/logs
    mkdir -p /app/aggregator
    mkdir -p /app/query

    # Generate log files with spaces in names
    echo "Generating logs..."
    for i in $(seq 1 50000); do
        echo "$RANDOM,Log message $i from web server 01" >> "/app/logs/web server 01.log"
        echo "$RANDOM,Log message $i from db server 02" >> "/app/logs/db server 02.log"
    done

    # Create C aggregator
    cat << 'EOF' > /app/aggregator/aggregator.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <json-c/json.h>

#define MAX_LOGS 150000

typedef struct {
    long long timestamp;
    char message[256];
} LogEntry;

LogEntry logs[MAX_LOGS];
int log_count = 0;

void read_logs() {
    DIR *d;
    struct dirent *dir;
    d = opendir("/app/logs");
    if (d) {
        while ((dir = readdir(d)) != NULL) {
            if (strstr(dir->d_name, ".log")) {
                char cmd[512];
                // Flawed implementation: popen with cat, breaks on spaces
                sprintf(cmd, "cat /app/logs/%s", dir->d_name);
                FILE *fp = popen(cmd, "r");
                if (fp) {
                    char line[512];
                    while (fgets(line, sizeof(line), fp)) {
                        long long ts;
                        char msg[256];
                        if (sscanf(line, "%lld,%255[^\n]", &ts, msg) == 2) {
                            if (log_count < MAX_LOGS) {
                                logs[log_count].timestamp = ts;
                                strcpy(logs[log_count].message, msg);
                                log_count++;
                            }
                        }
                    }
                    pclose(fp);
                }
            }
        }
        closedir(d);
    }
}

void sort_logs() {
    // Flawed implementation: bubble sort
    for (int i = 0; i < log_count - 1; i++) {
        for (int j = 0; j < log_count - i - 1; j++) {
            if (logs[j].timestamp > logs[j+1].timestamp) {
                LogEntry temp = logs[j];
                logs[j] = logs[j+1];
                logs[j+1] = temp;
            }
        }
    }
}

void handle_client(int client_sock) {
    log_count = 0;
    read_logs();
    sort_logs();

    struct json_object *jarray = json_object_new_array();
    for (int i = 0; i < log_count; i++) {
        struct json_object *jobj = json_object_new_object();
        json_object_object_add(jobj, "timestamp", json_object_new_int64(logs[i].timestamp));
        json_object_object_add(jobj, "message", json_object_new_string(logs[i].message));
        json_object_array_add(jarray, jobj);
    }

    const char *json_str = json_object_to_json_string(jarray);
    send(client_sock, json_str, strlen(json_str), 0);
    close(client_sock);
    json_object_put(jarray);
}

int main() {
    int server_sock, client_sock;
    struct sockaddr_in server_addr, client_addr;
    socklen_t client_len = sizeof(client_addr);

    server_sock = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(server_sock, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    server_addr.sin_family = AF_INET;
    server_addr.sin_addr.s_addr = INADDR_ANY;
    server_addr.sin_port = htons(8080);

    bind(server_sock, (struct sockaddr*)&server_addr, sizeof(server_addr));
    listen(server_sock, 5);

    while (1) {
        client_sock = accept(server_sock, (struct sockaddr*)&client_addr, &client_len);
        handle_client(client_sock);
    }
    return 0;
}
EOF

    # Create Makefile with missing json-c link
    cat << 'EOF' > /app/aggregator/Makefile
all:
	gcc -O2 aggregator.c -o aggregator
EOF

    # Create Query API
    cat << 'EOF' > /app/query/api.py
from flask import Flask, jsonify
import socket
import json

app = Flask(__name__)

@app.route('/logs')
def get_logs():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.connect(('127.0.0.1', 8080))
        data = b""
        while True:
            chunk = s.recv(4096)
            if not chunk:
                break
            data += chunk
        s.close()
        return jsonify(json.loads(data.decode('utf-8')))
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(port=5000)
EOF

    # Create start script
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
cd /app/aggregator
nohup ./aggregator > /dev/null 2>&1 &
cd /app/query
nohup python3 api.py > /dev/null 2>&1 &
EOF
    chmod +x /app/start_services.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
