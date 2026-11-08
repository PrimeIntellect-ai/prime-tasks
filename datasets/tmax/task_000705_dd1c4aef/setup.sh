#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/async_service
    cd /home/user/async_service

    git init
    git config user.name "Dev Team"
    git config user.email "dev@example.com"

    # 1. Initial working state
    cat << 'EOF' > server.py
import asyncio
import json
import sys

def load_config():
    try:
        with open('config.json', 'r') as f:
            return json.load(f)
    except Exception:
        print("Missing config.json")
        sys.exit(1)

async def handle_client(reader, writer):
    config = load_config()
    try:
        data = await reader.read(100)
        message = data.decode()
        addr = writer.get_extra_info('peername')

        # Simulate processing
        await asyncio.sleep(0.1)

        writer.write(data)
        await writer.drain()
    except asyncio.CancelledError:
        pass
    finally:
        writer.close()

async def main():
    server = await asyncio.start_server(handle_client, '127.0.0.1', 8888)
    async with server:
        await server.serve_forever()

if __name__ == '__main__':
    asyncio.run(main())
EOF

    cat << 'EOF' > config.json
{
    "SECRET_KEY": "sk_prod_99x2b_a1z"
}
EOF

    git add server.py config.json
    git commit -m "Initial commit: basic server and config"
    INITIAL_COMMIT=$(git rev-parse HEAD)

    # 2. Remove secret config
    git rm config.json
    echo "config.json" > .gitignore
    git add .gitignore
    git commit -m "Security fix: remove secret config from tracking"

    # 3. Introduce the bug (Culprit commit)
    cat << 'EOF' > server.py
import asyncio
import json
import sys

def load_config():
    try:
        with open('config.json', 'r') as f:
            return json.load(f)
    except Exception:
        print("Missing config.json")
        sys.exit(1)

async def heavy_background_task():
    # Bug: This task will run forever if not explicitly cancelled
    try:
        while True:
            await asyncio.sleep(1)
    except asyncio.CancelledError:
        pass

async def handle_client(reader, writer):
    config = load_config()
    bg_task = asyncio.create_task(heavy_background_task())
    try:
        data = await reader.read(100)
        if not data:
            return
        # Simulate processing
        await asyncio.sleep(0.1)

        writer.write(data)
        await writer.drain()
    except asyncio.CancelledError:
        # Bug: Caught cancellation but failed to cancel the background task!
        pass
    finally:
        writer.close()
        # MISSING: bg_task.cancel() and await bg_task

async def main():
    server = await asyncio.start_server(handle_client, '127.0.0.1', 8888)
    async with server:
        await server.serve_forever()

if __name__ == '__main__':
    asyncio.run(main())
EOF

    git add server.py
    git commit -m "Feature: add heavy background processing per request"
    CULPRIT_COMMIT=$(git rev-parse HEAD)

    mkdir -p /home/user/.truth
    echo "$CULPRIT_COMMIT" > /home/user/.truth/culprit_commit
    echo "sk_prod_99x2b_a1z" > /home/user/.truth/secret_key

    chown -R user:user /home/user/async_service /home/user/.truth
    chmod -R 777 /home/user
