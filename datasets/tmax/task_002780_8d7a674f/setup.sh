#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx
    pip3 install pytest websockets

    mkdir -p /home/user/ci_env

    cat << 'EOF' > /home/user/ci_env/nginx.conf
worker_processes 1;
daemon off;
error_log /tmp/error.log;
pid /tmp/nginx.pid;

events {
    worker_connections 1024;
}

http {
    client_body_temp_path /tmp/client_body;
    fastcgi_temp_path /tmp/fastcgi_temp;
    proxy_temp_path /tmp/proxy_temp;
    scgi_temp_path /tmp/scgi_temp;
    uwsgi_temp_path /tmp/uwsgi_temp;

    access_log /tmp/access.log;

    server {
        listen 8080;
        server_name localhost;

        location / {
            proxy_pass http://127.0.0.1:9000;
            proxy_http_version 1.1;
            # MISSING WEBSOCKET HEADERS HERE
        }
    }
}
EOF

    cat << 'EOF' > /home/user/ci_env/emulator.py
import asyncio
import websockets

def process_command(command: str) -> str:
    # TODO: Implement stack machine
    return "ERROR"

async def handler(websocket):
    async for message in websocket:
        try:
            result = process_command(message)
            await websocket.send(result)
        except Exception:
            await websocket.send("ERROR")

async def main():
    async with websockets.serve(handler, "127.0.0.1", 9000):
        await asyncio.Future()  # run forever

if __name__ == "__main__":
    asyncio.run(main())
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
