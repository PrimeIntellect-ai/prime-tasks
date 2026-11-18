#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server build-essential libhiredis-dev curl
    pip3 install pytest fastapi uvicorn

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/app/config /home/user/app/src /home/user/app/bin /home/user/archives /home/user/data/test_vol/dir1

    # Create excludes.conf in UTF-16LE
    echo -e "temp.dat\nignore.log" | iconv -f UTF-8 -t UTF-16LE > /home/user/app/config/excludes.conf

    # Create data files
    echo "Important data" > /home/user/data/test_vol/data.txt
    echo "Trash" > /home/user/data/test_vol/temp.dat

    # Create symlink loop
    ln -s /home/user/data/test_vol/dir1 /home/user/data/test_vol/dir1/loop

    # Skeleton C code
    cat << 'EOF' > /home/user/app/src/archiver.c
#include <stdio.h>
#include <stdlib.h>

int main() {
    // TODO: Implement archiver daemon
    return 0;
}
EOF

    # Python proxy to act as Nginx
    cat << 'EOF' > /home/user/proxy.py
import socket
from fastapi import FastAPI, Request, HTTPException
import uvicorn

app = FastAPI()

@app.post("/backup")
async def backup(request: Request):
    auth = request.headers.get("Authorization")
    if auth != "Bearer disk-admin-token-99":
        raise HTTPException(status_code=401, detail="Unauthorized")

    body = await request.body()
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.connect(("127.0.0.1", 9000))
        s.sendall(body)
        resp = s.recv(1024)
        s.close()
        return resp.decode("utf-8")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=8080)
EOF

    chmod -R 777 /home/user
