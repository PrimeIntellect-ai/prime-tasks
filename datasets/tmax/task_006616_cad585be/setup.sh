#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/app/models
    mkdir -p /home/user/app/libecc

    cat << 'EOF' > /home/user/app/models/file_meta.py
from .checksum_data import ChecksumData

class FileMeta:
    name = "FileMeta"
    def get_related(self):
        return ChecksumData
EOF

    cat << 'EOF' > /home/user/app/models/checksum_data.py
from .file_meta import FileMeta

class ChecksumData:
    name = "ChecksumData"
    def get_related(self):
        return FileMeta
EOF

    cat << 'EOF' > /home/user/app/models/__init__.py
EOF

    cat << 'EOF' > /home/user/app/setup_db.py
import sqlite3
import sys
import os

sys.path.append(os.path.dirname(os.path.abspath(__file__)))

# This will fail due to circular import if not fixed
from models.file_meta import FileMeta
from models.checksum_data import ChecksumData

def setup():
    conn = sqlite3.connect('/home/user/app/test.db')
    conn.execute('CREATE TABLE IF NOT EXISTS file_meta (id INTEGER PRIMARY KEY, name TEXT)')
    conn.execute('CREATE TABLE IF NOT EXISTS checksum_data (id INTEGER PRIMARY KEY, file_id INTEGER, checksum TEXT)')
    conn.commit()
    conn.close()
    print("DB setup complete.")

if __name__ == "__main__":
    setup()
EOF

    cat << 'EOF' > /home/user/app/libecc/ecc.c
#include <stdlib.h>
#include <string.h>

char* calculate_checksum(const char* input) {
    int len = strlen(input);
    // VULNERABILITY: allocates len + 1, but we append 4 bytes later
    char* out = (char*)malloc(len + 1); 
    if(!out) return NULL;

    strcpy(out, input);
    // Out of bounds write
    strcat(out, "1234"); 

    return out;
}
EOF

    cat << 'EOF' > /home/user/app/libecc/build.sh
#!/bin/bash
cd /home/user/app/libecc
gcc -shared -o libecc.so -fPIC ecc.c
EOF
    chmod +x /home/user/app/libecc/build.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
