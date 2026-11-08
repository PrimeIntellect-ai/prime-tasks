#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ wget tar gzip coreutils
    pip3 install pytest

    mkdir -p /home/user/project
    wget -O /home/user/project/json.hpp https://raw.githubusercontent.com/nlohmann/json/v3.11.2/single_include/nlohmann/json.hpp

    python3 -c "
with open('/home/user/project/archive.pack', 'wb') as f:
    f.write(b'{\"files\":[{\"name\":\"config.json\",\"offset\":0,\"size\":22},{\"name\":\"firmware.elf\",\"offset\":22,\"size\":16}]}')
    f.write(b'\x00')
    f.write(b'{\"version\":1,\"debug\":1}')
    f.write(b'\x7f\x45\x4c\x46\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
