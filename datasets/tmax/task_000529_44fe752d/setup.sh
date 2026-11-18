#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make wget
pip3 install pytest

mkdir -p /app/cJSON-1.7.15
wget -q https://raw.githubusercontent.com/DaveGamble/cJSON/v1.7.15/cJSON.c -O /app/cJSON-1.7.15/cJSON.c
wget -q https://raw.githubusercontent.com/DaveGamble/cJSON/v1.7.15/cJSON.h -O /app/cJSON-1.7.15/cJSON.h

cat << 'EOF' > /app/cJSON-1.7.15/Makefile
all: cJSON.o
	as rcs libcjson.a cJSON.o # PERTURBATION: 'as' instead of 'ar'

cJSON.o: cJSON.c
	gcc -c -O2 -fPIC cJSON.c -o cJSON.o
EOF

mkdir -p /app/uptime-analyzer
cat << 'EOF' > /app/uptime-analyzer/Makefile
analyzer: analyzer.c
	gcc -O2 analyzer.c -I../cJSON-1.7.15 -L../cJSON-1.7.15 -lcjson -lm -o analyzer
EOF

cat << 'EOF' > /app/uptime-analyzer/analyzer.c
#include <stdio.h>
#include <stdlib.h>
#include "cJSON.h"

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    cJSON *json = cJSON_Parse(argv[1]);
    if (!json) return 1;

    cJSON *server = cJSON_GetObjectItem(json, "server");
    cJSON *pings = cJSON_GetObjectItem(json, "pings");
    cJSON *missed = cJSON_GetObjectItem(json, "missed");

    if (server && pings && missed) {
        // BUG: Integer division causes truncation before conversion to double
        double uptime = ((pings->valueint - missed->valueint) / pings->valueint) * 100.0;
        printf("Server %s: %.2f%%\n", server->valuestring, uptime);
    }

    cJSON_Delete(json);
    return 0;
}
EOF

mkdir -p /oracle
cat << 'EOF' > /oracle/uptime_oracle.py
#!/usr/bin/env python3
import sys
import json

def main():
    if len(sys.argv) < 2:
        sys.exit(1)
    try:
        data = json.loads(sys.argv[1])
        server = data["server"]
        pings = int(data["pings"])
        missed = int(data["missed"])
        uptime = ((pings - missed) / float(pings)) * 100.0
        print(f"Server {server}: {uptime:.2f}%")
    except Exception as e:
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF
chmod +x /oracle/uptime_oracle.py

useradd -m -s /bin/bash user || true
chmod -R 777 /app
chmod -R 777 /home/user
