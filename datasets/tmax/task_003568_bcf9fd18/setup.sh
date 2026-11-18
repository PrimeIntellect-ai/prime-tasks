#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip make gcc wget tar jq bc locales
    pip3 install pytest

    # Generate locales
    locale-gen fr_FR.UTF-8
    update-locale

    # Download and extract cJSON
    mkdir -p /app/vendored
    wget -q https://github.com/DaveGamble/cJSON/archive/refs/tags/v1.7.15.tar.gz -O /tmp/cjson.tar.gz
    tar -xzf /tmp/cjson.tar.gz -C /app/vendored
    mv /app/vendored/cJSON-1.7.15 /app/vendored/cJSON
    rm /tmp/cjson.tar.gz

    # Apply perturbations to Makefile
    cd /app/vendored/cJSON
    # Ensure the exact strings exist or modify them so the tests pass
    sed -i 's/LDFLAGS += -lm/LDFLAGS += /' Makefile
    sed -i 's/CFLAGS += -std=c89/CFLAGS += -std=c89 -DENABLE_LOCALES=1/' Makefile

    # Fallback if the sed didn't work as expected by the test
    if grep -q "LDFLAGS += -lm" Makefile; then
        sed -i 's/LDFLAGS += -lm/LDFLAGS += /g' Makefile
    fi
    if ! grep -q -- "-DENABLE_LOCALES=1" Makefile; then
        echo "CFLAGS += -DENABLE_LOCALES=1" >> Makefile
    fi

    # Generate Corpora
    mkdir -p /app/corpora/clean /app/corpora/evil
    python3 -c '
import os, json, random
for i in range(50):
    with open(f"/app/corpora/clean/clean_{i}.json", "w") as f:
        json.dump({"cpu": random.uniform(10, 90), "mem": random.randint(100, 8000), "status": "ok"}, f)

for i in range(50):
    with open(f"/app/corpora/evil/evil_{i}.json", "wb") as f:
        choice = i % 3
        if choice == 0:
            f.write(b"{\"cpu\": 45.2, \"mem\": 1024, \"status\": \"ok\", \"bad\": \"\xff\xfe\"}")
        elif choice == 1:
            nesting = "{\"a\":" * 200 + "1" + "}" * 200
            f.write(nesting.encode())
        else:
            f.write(b"{\"cpu\": 1e999, \"mem\": 1024, \"status\": \"ok\"}")
'

    # Create user
    useradd -m -s /bin/bash user || true

    # Set permissions
    chown -R user:user /app/vendored/cJSON
    chmod -R 777 /home/user
