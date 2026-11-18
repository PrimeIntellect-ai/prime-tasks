#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc patch wget
pip3 install pytest websockets

# Install websocat manually as it is not in the default Ubuntu 22.04 repos
wget -qO /usr/local/bin/websocat https://github.com/vi/websocat/releases/download/v1.11.0/websocat.x86_64-unknown-linux-musl
chmod +x /usr/local/bin/websocat

useradd -m -s /bin/bash user || true

# Create policy.conf
cat << 'EOF' > /home/user/policy.conf
AllowPort 80
MaxConns 10
AdminUser root
EOF

# Create update.patch
cat << 'EOF' > /home/user/update.patch
--- policy.conf
+++ policy.conf
@@ -1,3 +1,4 @@
 AllowPort 80
+AllowPort 443
 MaxConns 10
-AdminUser root
+AdminUser admin
EOF

# Create ws_server.py
cat << 'EOF' > /home/user/ws_server.py
import asyncio
import websockets

async def handler(websocket, path):
    async for message in websocket:
        with open('/home/user/audit_log.json', 'a') as f:
            f.write(message + '\n')

start_server = websockets.serve(handler, "127.0.0.1", 8080)
asyncio.get_event_loop().run_until_complete(start_server)
asyncio.get_event_loop().run_forever()
EOF

chmod -R 777 /home/user
