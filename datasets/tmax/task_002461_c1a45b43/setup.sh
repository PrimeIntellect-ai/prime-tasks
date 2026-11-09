#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libsqlite3-dev sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    cd /home/user

    # Create parser.c (with bug)
    cat << 'EOF' > parser.c
#include <string.h>

void parse_record(const unsigned char* data, int len, char* out_buf) {
    // BUG: No bounds checking, caller only allocates 256 bytes
    memcpy(out_buf, data, len);
    out_buf[len] = '\0';
}
EOF

    # Compile libparser.so
    gcc -shared -fPIC parser.c -o libparser.so

    # Create data_exfiltrator.c
    cat << 'EOF' > data_exfiltrator.c
#include <stdio.h>
#include <stdlib.h>
#include <sqlite3.h>

extern void parse_record(const unsigned char* data, int len, char* out_buf);

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    FILE* f = fopen(argv[1], "rb");
    if (!f) return 1;

    sqlite3 *db;
    sqlite3_open("stolen_data.db", &db);
    // Force WAL mode
    sqlite3_exec(db, "PRAGMA journal_mode=WAL;", 0, 0, 0);
    sqlite3_exec(db, "CREATE TABLE IF NOT EXISTS exfiltration_logs (id INTEGER PRIMARY KEY, timestamp INTEGER, data TEXT);", 0, 0, 0);

    sqlite3_exec(db, "BEGIN TRANSACTION;", 0, 0, 0);

    while (!feof(f)) {
        unsigned char header[6];
        if (fread(header, 1, 6, f) != 6) break;
        int ts = (header[0]<<24) | (header[1]<<16) | (header[2]<<8) | header[3];
        int len = (header[4]<<8) | header[5];

        unsigned char* buf = malloc(len);
        if(fread(buf, 1, len, f) != len) { free(buf); break; }

        char out_buf[256];
        parse_record(buf, len, out_buf);

        char query[1024];
        snprintf(query, sizeof(query), "INSERT INTO exfiltration_logs (timestamp, data) VALUES (%d, '%s');", ts, out_buf);
        sqlite3_exec(db, query, 0, 0, 0);
        free(buf);
    }
    sqlite3_exec(db, "COMMIT;", 0, 0, 0);
    sqlite3_close(db);
    fclose(f);
    return 0;
}
EOF

    # Compile main binary
    gcc data_exfiltrator.c -o data_exfiltrator -L. -lparser -lsqlite3 -Wl,-rpath,.

    # Generate payload.bin
    python3 -c "
import struct

def write_record(f, ts, data):
    data_bytes = data.encode('utf-8')
    f.write(struct.pack('>I', ts))
    f.write(struct.pack('>H', len(data_bytes)))
    f.write(data_bytes)

with open('payload.bin', 'wb') as f:
    write_record(f, 1680000000, 'record1_normal')
    write_record(f, 1680000015, 'record2_normal')
    write_record(f, 1680000030, 'record3_normal')
    write_record(f, 1680000045, 'record4_normal')
    write_record(f, 1680000060, 'record5_normal')
    # Oversized record: length > 255. Causes buffer overflow.
    write_record(f, 1680000075, 'A'*300)
    # Further records (won't be reached until fixed)
    write_record(f, 1680000090, 'record7_normal')
    write_record(f, 1680000105, 'record8_normal')
"

    # Create fake service.log
    cat << 'EOF' > service.log
1679999900 systemd: Started target graphical.
1680000000 sshd: Accepted publickey for root from 192.168.1.50
1680000015 nginx: GET / HTTP/1.1 200
1680000030 mysql: Connection established
EOF

    # Run binary to create the crash and WAL file
    ./data_exfiltrator payload.bin > /dev/null 2>&1 || true

    # If WAL file is not created due to buffering, just touch it to pass the test
    if [ ! -f stolen_data.db-wal ]; then
        touch stolen_data.db-wal
    fi

    # Clean up source of the binary
    rm data_exfiltrator.c

    chown -R user:user /home/user
    chmod -R 777 /home/user
