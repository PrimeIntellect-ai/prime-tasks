#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        python3-websockets \
        gcc \
        binutils \
        jq \
        curl \
        wget
    pip3 install pytest websockets

    # Download websocat
    wget -qO /usr/local/bin/websocat https://github.com/vi/websocat/releases/latest/download/websocat.x86_64-unknown-linux-musl
    chmod +x /usr/local/bin/websocat

    mkdir -p /home/user/artifact/bin /home/user/artifact/lib
    cd /home/user/artifact

    cat << 'EOF' > libgamma.c
void gamma_func() {}
EOF

    cat << 'EOF' > libbeta.c
void beta_func() {}
EOF

    cat << 'EOF' > libalpha.c
void gamma_func();
void alpha_func() { gamma_func(); }
EOF

    cat << 'EOF' > server.c
void alpha_func();
void beta_func();
int main() { alpha_func(); beta_func(); return 0; }
EOF

    gcc -shared -fPIC -o lib/libgamma.so libgamma.c
    gcc -shared -fPIC -o lib/libbeta.so libbeta.c
    gcc -shared -fPIC -o lib/libalpha.so libalpha.c -L./lib -lgamma -Wl,-rpath='$ORIGIN'
    gcc -o bin/server server.c -L./lib -lalpha -lbeta -Wl,-rpath-link=./lib -Wl,-rpath='$ORIGIN/../lib'

    rm *.c

    cat << 'EOF' > /home/user/ws_server.py
import asyncio
import websockets

async def handler(websocket, path):
    try:
        msg = await websocket.recv()
        with open('/home/user/ws_received.json', 'w') as f:
            f.write(msg)
    except Exception:
        pass

start_server = websockets.serve(handler, '127.0.0.1', 9090)
asyncio.get_event_loop().run_until_complete(start_server)
asyncio.get_event_loop().run_forever()
EOF

    useradd -m -s /bin/bash user || true

    # Start background server on bash login/interactive shell
    echo "nohup python3 /home/user/ws_server.py >/dev/null 2>&1 &" >> /home/user/.bashrc
    echo "nohup python3 /home/user/ws_server.py >/dev/null 2>&1 &" >> /root/.bashrc

    chmod -R 777 /home/user
