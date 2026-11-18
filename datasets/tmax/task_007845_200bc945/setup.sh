#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make sqlite3
    pip3 install pytest

    mkdir -p /home/user/mobile_pipeline/src
    mkdir -p /home/user/mobile_pipeline/build

    python3 -c '
with open("/home/user/mobile_pipeline/Makefile", "w") as f:
    f.write("CC=gcc\nCFLAGS=-Wall -fPIC -shared\n\nall: build/libcore.so\n\nbuild/libcore.so: src/core.c\n    $(CC) $(CFLAGS) -o build/libcore.so src/core.c\n")
'

    cat << 'EOF' > /home/user/mobile_pipeline/src/core.c
#include <stdio.h>

int process_data(int input) {
    int multiplier = 42
    return input * multiplier;
}
EOF

    cat << 'EOF' > /home/user/mobile_pipeline/metadata.xml
<?xml version="1.0" encoding="UTF-8"?>
<build>
    <version>1.4.2-beta</version>
    <target>libcore.so</target>
</build>
EOF

    sqlite3 /home/user/mobile_pipeline/ota.db "CREATE TABLE releases (id INTEGER PRIMARY KEY, version TEXT, target TEXT);"
    sqlite3 /home/user/mobile_pipeline/ota.db "INSERT INTO releases (version, target) VALUES ('1.4.1', 'libcore.so');"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
