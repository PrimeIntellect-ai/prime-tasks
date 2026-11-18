#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip python3-venv gcc
pip3 install pytest

mkdir -p /home/user/waf_project
cd /home/user/waf_project

cat << 'EOF' > waf.c
#include <stdint.h>
#include <string.h>

int analyze_payload(const char* payload, uint32_t checksum) {
    uint32_t expected = strlen(payload) * 42;
    if (checksum != expected) return -1;

    int state = 0;
    for(int i=0; payload[i] != '\0'; i++) {
        if(state == 0 && payload[i] == 'S') state = 1;
        else if(state == 1 && payload[i] == 'E') state = 2;
        else if(state == 2 && payload[i] == 'L') state = 3;
        else if(state == 3 && payload[i] == 'E') state = 4;
        else if(state == 4 && payload[i] == 'C') state = 5;
        else if(state == 5 && payload[i] == 'T') return 1;
        else state = 0;
    }
    return 0;
}
EOF

cat << 'EOF' > build.sh
#!/bin/bash
# Broken build script
gcc -o libwaf.so waf.c
EOF
chmod +x build.sh

cat << 'EOF' > api.py
import ctypes
from fastapi import FastAPI
from pydantic import BaseModel
import uvicorn

app = FastAPI()

# TODO: Fix ctypes loading and types
# waf = ctypes.CDLL("./libwaf.so")

class PayloadReq(BaseModel):
    data: str

# TODO: Implement POST /analyze
EOF

cat << 'EOF' > requirements.txt
fastapi==0.104.1
uvicorn==0.24.0
pydantic==2.5.2
requests==2.31.0
EOF

python3 -m venv /home/user/venv
/home/user/venv/bin/pip install -r requirements.txt

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
