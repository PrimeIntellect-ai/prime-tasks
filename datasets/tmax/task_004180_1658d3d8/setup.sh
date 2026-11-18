#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    gcc \
    redis-server \
    supervisor

pip3 install --default-timeout=100 pytest aiosmtpd redis

mkdir -p /app/oracle
mkdir -p /home/user

# Create Oracle source and compile
cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>

int main() {
    unsigned char buf[1024];
    size_t len = 0;
    int c;
    while ((c = getchar()) != EOF && len < 1024) {
        buf[len++] = (unsigned char)c;
    }
    for (size_t i = 0; i < len; i++) {
        putchar(buf[len - 1 - i] ^ 0x5A);
    }
    return 0;
}
EOF

gcc /tmp/oracle.c -o /app/oracle/obfuscator_oracle
strip /app/oracle/obfuscator_oracle
rm /tmp/oracle.c

# Create smtp_receiver.py
cat << 'EOF' > /app/smtp_receiver.py
#!/usr/bin/env python3
import asyncio
from aiosmtpd.controller import Controller
import redis

r = redis.Redis(host='localhost', port=6379, db=0)

class CustomHandler:
    async def handle_DATA(self, server, session, envelope):
        r.rpush('mail_queue', envelope.content)
        return '250 OK'

if __name__ == '__main__':
    controller = Controller(CustomHandler(), hostname='127.0.0.1', port=2525)
    controller.start()
    try:
        asyncio.get_event_loop().run_forever()
    except KeyboardInterrupt:
        pass
EOF
chmod +x /app/smtp_receiver.py

# Create archive_worker.py
cat << 'EOF' > /app/archive_worker.py
#!/usr/bin/env python3
import os
import redis
import subprocess

r = redis.Redis(host='localhost', port=6379, db=0)
obfuscator_bin = os.environ.get('OBFUSCATOR_BIN')

while True:
    _, data = r.blpop('mail_queue')
    p = subprocess.Popen([obfuscator_bin], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    out, _ = p.communicate(input=data)
    r.set('archive_latest', out)
EOF
chmod +x /app/archive_worker.py

# Create supervisord.conf skeleton
cat << 'EOF' > /home/user/supervisord.conf
[unix_http_server]
file=/tmp/supervisor.sock
chmod=0777

[supervisord]
logfile=/tmp/supervisord.log
pidfile=/tmp/supervisord.pid
nodaemon=false

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[supervisorctl]
serverurl=unix:///tmp/supervisor.sock
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
