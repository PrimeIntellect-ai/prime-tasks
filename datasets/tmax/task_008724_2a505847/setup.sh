#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc patch
    pip3 install pytest websockets

    mkdir -p /home/user

    cat << 'EOF' > /home/user/equations.txt
+ 5 3
* 2 + 4 6
- * 10 2 5
/ + 20 10 3
+ * 2 3 * 4 5
EOF

    cat << 'EOF' > /home/user/client.py
import asyncio
import websockets

equations = open('/home/user/equations.txt').read().strip().split('\n')

async def run_client():
    ws = await websockets.connect('ws://localhost:8080')
    out = open('/home/user/output.txt', 'w')
    for eq in equations:
        await ws.send(eq)
        res = await ws.recv()
        out.write(res + '\n')
    out.close()
    await ws.close()

if __name__ == '__main__':
    print "Running client..."
    loop = asyncio.get_event_loop()
    loop.run_until_complete(run_client())
EOF

    cat << 'EOF' > /home/user/upgrade.patch
--- client.py
+++ client.py
@@ -14,6 +14,6 @@
     await ws.close()

 if __name__ == '__main__':
-    print "Running client..."
+    print("Running client...")
     loop = asyncio.get_event_loop()
     loop.run_until_complete(run_client())
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
