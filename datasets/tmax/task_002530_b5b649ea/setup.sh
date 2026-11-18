#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cmake g++ make git wget
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /app/simdjson-3.6.0 /app/corpus/clean /app/corpus/evil /home/user/src /home/user/local

    # Download simdjson 3.6.0
    wget -qO- https://github.com/simdjson/simdjson/archive/refs/tags/v3.6.0.tar.gz | tar xz -C /app/simdjson-3.6.0 --strip-components=1

    # Perturb CMakeLists.txt
    sed -i 's/CXX_STANDARD 17/CXX_STANDARD 11/g' /app/simdjson-3.6.0/CMakeLists.txt
    sed -i 's/CXX_STANDARD 20/CXX_STANDARD 11/g' /app/simdjson-3.6.0/CMakeLists.txt
    # Ensure it's there for the test if it wasn't modified by sed
    if ! grep -q "CXX_STANDARD 11" /app/simdjson-3.6.0/CMakeLists.txt; then
        sed -i '1s/^/set(CMAKE_CXX_STANDARD 11)\n/' /app/simdjson-3.6.0/CMakeLists.txt
    fi

    # Create corpus using Python
    python3 -c '
import json
import random

# clean
for i in range(10):
    with open(f"/app/corpus/clean/clean_{i}.json", "w") as f:
        json.dump({"status": "success", "data": [random.uniform(-10.0, 10.0) for _ in range(256)]}, f)

# evil
# 1. Malformed
with open("/app/corpus/evil/evil_1.json", "w") as f:
    f.write("{\"status\": \"success\", \"data\": [1, 2, 3")
# 2. Correct JSON, but status: error
with open("/app/corpus/evil/evil_2.json", "w") as f:
    json.dump({"status": "error", "data": [0.0]*256}, f)
# 3. 255 elements
with open("/app/corpus/evil/evil_3.json", "w") as f:
    json.dump({"status": "success", "data": [0.0]*255}, f)
# 4. 257 elements
with open("/app/corpus/evil/evil_4.json", "w") as f:
    json.dump({"status": "success", "data": [0.0]*257}, f)
# 5. String instead of float
with open("/app/corpus/evil/evil_5.json", "w") as f:
    json.dump({"status": "success", "data": [0.0]*255 + ["0.0"]}, f)
# 6. Value > 10.0
with open("/app/corpus/evil/evil_6.json", "w") as f:
    json.dump({"status": "success", "data": [0.0]*255 + [10.1]}, f)
# 7. Value < -10.0
with open("/app/corpus/evil/evil_7.json", "w") as f:
    json.dump({"status": "success", "data": [0.0]*255 + [-10.1]}, f)
# 8. Missing status
with open("/app/corpus/evil/evil_8.json", "w") as f:
    json.dump({"data": [0.0]*256}, f)
# 9. Missing data
with open("/app/corpus/evil/evil_9.json", "w") as f:
    json.dump({"status": "success"}, f)
# 10. Contains null
with open("/app/corpus/evil/evil_10.json", "w") as f:
    json.dump({"status": "success", "data": [0.0]*255 + [None]}, f)
'

    chmod -R 777 /app
    chown -R user:user /home/user
    chmod -R 777 /home/user
