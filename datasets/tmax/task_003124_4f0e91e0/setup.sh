#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest websockets

cat << 'EOF' > /tmp/test_client.py
import asyncio
import websockets
import json
import sys

workers = {
    "type": "workers",
    "data": {
        "w-linux-gcc": ["gcc", "make", "bash"],
        "w-mac-clang": ["clang", "make", "bash"],
        "w-windows-msvc": ["msvc", "cmake", "powershell"],
        "w-polyglot": ["gcc", "python", "node", "bash"]
    }
}

dsl_script = """
TARGET init
REQUIRES bash
END

TARGET compile_c
REQUIRES gcc
REQUIRES make
AFTER init
END

TARGET compile_py
REQUIRES python
AFTER init
END

TARGET link
REQUIRES bash
AFTER compile_c
AFTER compile_py
END

TARGET package
REQUIRES node
AFTER link
END
"""

dsl = {
    "type": "dsl",
    "script": dsl_script
}

async def run_test():
    try:
        async with websockets.connect("ws://localhost:9000") as websocket:
            await websocket.send(json.dumps(workers))
            await websocket.send(json.dumps(dsl))

            expected_tasks = ["init", "compile_c", "compile_py", "link", "package"]
            completed = []

            while True:
                msg = await websocket.recv()
                data = json.loads(msg)

                if data.get("type") == "done":
                    break
                elif data.get("type") == "execute":
                    task = data["task"]
                    completed.append(task)
                    # Simulate work
                    await asyncio.sleep(0.1)
                    await websocket.send(json.dumps({"type": "completed", "task": task}))
                else:
                    print(f"Unknown message: {data}")
                    sys.exit(1)

            print("Client finished successfully.")
    except Exception as e:
        print(f"Test failed: {e}")
        sys.exit(1)

if __name__ == "__main__":
    asyncio.run(run_test())
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
