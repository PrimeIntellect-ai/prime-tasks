#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 gcc make procps
    pip3 install pytest websockets

    mkdir -p /home/user/project
    cd /home/user/project

    # 1. Create SQLite DB
    sqlite3 db.sqlite3 "CREATE TABLE configurations (id INTEGER PRIMARY KEY, name TEXT);"
    sqlite3 db.sqlite3 "INSERT INTO configurations (id, name) VALUES (1, 'stadium_1');"

    # 2. Create the Python 2 migration script
    cat << 'EOF' > migrate_db.py
import sqlite3

def run_migration():
    print "Connecting to database..."
    conn = sqlite3.connect('/home/user/project/db.sqlite3')
    c = conn.cursor()
    print "Adding max_angle column..."
    c.execute("ALTER TABLE configurations ADD COLUMN max_angle INTEGER")
    conn.commit()
    print "Migration successful!"

if __name__ == '__main__':
    run_migration()
EOF

    # 3. Create the buggy solver.c
    cat << 'EOF' > solver.c
#include <stdio.h>
#include <math.h>

int main() {
    double V = 40.0;
    double g = 9.81;
    int best_angle = -1;

    for (int theta = 1; theta <= 89; theta++) {
        // BUG: Trigonometric functions in C expect radians, not degrees.
        double rad = theta; 
        double R = (V * V * sin(2 * rad)) / g;
        double H = (V * V * sin(rad) * sin(rad)) / (2 * g);

        if (R >= 99.0 && R <= 101.0 && H <= 25.0) {
            if (theta > best_angle) {
                best_angle = theta;
            }
        }
    }
    printf("%d\n", best_angle);
    return 0;
}
EOF

    # 4. Create the broken Makefile (4 spaces instead of tab)
    cat << 'EOF' > Makefile
solver: solver.c
    gcc -o solver solver.c
EOF

    # 5. Create the WebSocket server
    cat << 'EOF' > ws_server.py
import asyncio
import websockets
import json

async def handler(websocket, path):
    try:
        message = await websocket.recv()
        data = json.loads(message)
        if "angle" in data:
            with open("/home/user/project/ws_success.log", "w") as f:
                f.write(f"Received angle: {data['angle']}")
        await websocket.send("OK")
    except Exception:
        pass

async def main():
    async with websockets.serve(handler, "localhost", 8080):
        await asyncio.Future()

asyncio.run(main())
EOF

    # Ensure the WebSocket server starts when bash is launched
    cat << 'EOF' >> /etc/bash.bashrc
if ! pgrep -f ws_server.py > /dev/null; then
    python3 /home/user/project/ws_server.py &
    sleep 1
fi
EOF

    # 6. Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/project
    chmod -R 777 /home/user
