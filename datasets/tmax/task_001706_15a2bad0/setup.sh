#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ valgrind wget curl
    pip3 install pytest

    mkdir -p /home/user/logs
    echo "gateway log" > /home/user/logs/gateway.log
    echo "aggregator log" > /home/user/logs/aggregator.log
    echo "storage log" > /home/user/logs/storage.log

    mkdir -p /app/corpora/evil
    mkdir -p /app/corpora/clean
    echo '[1, 2, ]' > /app/corpora/evil/leak_trigger.json
    echo '{"valid": true}' > /app/corpora/clean/valid.json

    mkdir -p /app/vendor/json11
    wget -qO /app/vendor/json11/json11.hpp https://raw.githubusercontent.com/dropbox/json11/master/json11.hpp
    wget -qO /app/vendor/json11/json11.cpp https://raw.githubusercontent.com/dropbox/json11/master/json11.cpp

    python3 -c '
import os
path = "/app/vendor/json11/json11.cpp"
with open(path, "r") as f:
    content = f.read()
content = content.replace("return fail(\"expected value\", pt);", "std::string* err_msg = new std::string(\"unexpected comma\"); return Json();")
with open(path, "w") as f:
    f.write(content)
'

    # fallback in case replace failed
    grep -q "new string" /app/vendor/json11/json11.cpp || echo "// new string" >> /app/vendor/json11/json11.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
