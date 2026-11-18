#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make binutils
    pip3 install pytest websockets asyncio

    mkdir -p /home/user/ws_proxy/packages
    cd /home/user/ws_proxy/packages

    # Create library source files
    cat << 'EOF' > ws_v1.c
extern void auth_basic();
void ws_init() { auth_basic(); }
EOF

    cat << 'EOF' > ws_v2.c
extern void auth_check_v3();
void ws_init_secure() { auth_check_v3(); }
EOF

    cat << 'EOF' > auth_v1.c
void auth_basic() {}
EOF

    cat << 'EOF' > auth_v2.c
void auth_check_v2() {}
EOF

    cat << 'EOF' > auth_v3.c
extern void filter_strict();
void auth_check_v3() { filter_strict(); }
EOF

    cat << 'EOF' > filter_v1.c
void filter_basic() {}
EOF

    cat << 'EOF' > filter_v2.c
void filter_strict() {}
EOF

    # Compile and archive libraries
    gcc -c ws_v1.c && ar rcs libws_v1.a ws_v1.o
    gcc -c ws_v2.c && ar rcs libws_v2.a ws_v2.o
    gcc -c auth_v1.c && ar rcs libauth_v1.a auth_v1.o
    gcc -c auth_v2.c && ar rcs libauth_v2.a auth_v2.o
    gcc -c auth_v3.c && ar rcs libauth_v3.a auth_v3.o
    gcc -c filter_v1.c && ar rcs libfilter_v1.a filter_v1.o
    gcc -c filter_v2.c && ar rcs libfilter_v2.a filter_v2.o

    # Clean up source and object files
    rm *.c *.o

    cd /home/user/ws_proxy

    # Create server.c
    cat << 'EOF' > server.c
#include <stdlib.h>
#include <stdio.h>

extern void ws_init_secure();

int main() {
    ws_init_secure();
    // Start a mock WebSocket server in Python
    system("python3 -c '\n\
import asyncio, websockets\n\
async def handler(websocket, path):\n\
    try:\n\
        msg = await websocket.recv()\n\
        if \"<script>alert(1)</script>\" in msg:\n\
            await websocket.send(\"{\\\"status\\\": \\\"blocked\\\", \\\"reason\\\": \\\"XSS detected\\\"}\")\n\
    except websockets.exceptions.ConnectionClosed:\n\
        pass\n\
start_server = websockets.serve(handler, \"127.0.0.1\", 8080)\n\
asyncio.get_event_loop().run_until_complete(start_server)\n\
asyncio.get_event_loop().run_forever()\n\
'");
    return 0;
}
EOF

    # Create Makefile
    cat << 'EOF' > Makefile
proxy_server: server.c
	gcc server.c -L./packages -lws_v1 -lauth_v1 -lfilter_v1 -o proxy_server
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
