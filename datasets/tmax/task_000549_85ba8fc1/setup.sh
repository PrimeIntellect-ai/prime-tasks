#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential wget cargo rustc
    pip3 install pytest

    mkdir -p /app/vendored
    cd /app/vendored
    wget https://github.com/nodejs/http-parser/archive/refs/tags/v2.9.4.tar.gz
    tar -xzf v2.9.4.tar.gz
    rm v2.9.4.tar.gz

    # Apply perturbation
    sed -i 's/CFLAGS += -Wall -Wextra/CFLAGS += -Wall -Wextra -Werror/' /app/vendored/http-parser-2.9.4/Makefile

    # Generate data
    cat << 'EOF' > /tmp/gen.py
import random
import os

random.seed(42)
urls = []
os.makedirs("/app/data", exist_ok=True)
with open("/app/data/requests.log", "wb") as f:
    for i in range(200000):
        has_score = random.random() > 0.3
        score = random.randint(1, 10000)
        url = f"/api/endpoint_{random.randint(1,500)}?ts={random.randint(1000,9999)}"
        if has_score:
            url += f"&score={score}"
            urls.append((score, url))

        req = f"GET {url} HTTP/1.1\r\nHost: localhost\r\nAccept: */*\r\n\r\n".encode('utf-8')
        f.write(req)
        if i < 199999:
            f.write(b"\r\n---REQUEST-BOUNDARY---\r\n")

urls.sort(key=lambda x: (-x[0], x[1]))
with open("/app/data/expected_top_urls.txt", "w") as f:
    for _, u in urls:
        f.write(u + "\n")
EOF
    python3 /tmp/gen.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app/vendored
    chmod -R 777 /app/data
    chmod -R 777 /home/user
