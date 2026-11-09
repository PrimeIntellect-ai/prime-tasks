#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gdb sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/ticket_402
    cd /home/user/ticket_402

    # 1. Create the SQLite database
    cat << 'EOF' > setup_db.py
import sqlite3

conn = sqlite3.connect('company.db')
c = conn.cursor()
c.execute('''CREATE TABLE employees (id INTEGER PRIMARY KEY, username TEXT, role TEXT, is_deleted INTEGER)''')
users = [
    ('alice_admin', 'admin', 0),
    ('bob_it', 'user', 0),
    ('charlie_root', 'admin', 1),
    ('dave_hr', 'user', 1),
    ('eve_sys', 'admin', 1)
]
c.executemany('INSERT INTO employees (username, role, is_deleted) VALUES (?, ?, ?)', users)
conn.commit()
conn.close()
EOF
    python3 setup_db.py
    rm setup_db.py

    # 2. Create the buggy parser.c
    cat << 'EOF' > parser.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <assert.h>

int main() {
    FILE *f = fopen("fs_dump.bin", "rb");
    if (!f) {
        printf("Could not open fs_dump.bin\n");
        return 1;
    }

    char header[4];
    fread(header, 1, 4, f);
    if (strncmp(header, "DUMP", 4) != 0) {
        printf("Invalid header\n");
        return 1;
    }

    uint16_t num_records;
    fread(&num_records, 2, 1, f);

    uint8_t i; // BUG: uint8_t max is 255. If num_records > 255, infinite loop!
    for (i = 0; i < num_records; i++) {
        uint8_t status;
        if (fread(&status, 1, 1, f) != 1) break;

        uint8_t name_len;
        fread(&name_len, 1, 1, f);

        char name[256] = {0};
        fread(name, 1, name_len, f);

        uint16_t data_len;
        fread(&data_len, 2, 1, f);

        // TODO: Add assertion here to ensure data_len < 10000

        if (status == 0) {
            FILE *out = fopen(name, "wb");
            if (out) {
                char *data = malloc(data_len);
                fread(data, 1, data_len, f);
                fwrite(data, 1, data_len, out);
                fclose(out);
                free(data);
                printf("Recovered deleted file: %s\n", name);
            }
        } else {
            fseek(f, data_len, SEEK_CUR);
        }
    }

    fclose(f);
    return 0;
}
EOF

    # 3. Create the fs_dump.bin binary file using Python
    cat << 'EOF' > make_dump.py
import struct

records = []
# Create 300 dummy records (active) to trigger the uint8_t overflow (>255)
for i in range(300):
    status = 1 # Active
    name = f"dummy_{i}.txt".encode('utf-8')
    name_len = len(name)
    data = b"x" * 10
    data_len = len(data)
    records.append(struct.pack(f"<BB{name_len}sH{data_len}s", status, name_len, name, data_len, data))

# Create 1 deleted record (the SQL query)
status = 0 # Deleted
name = b"recovered_query.sql"
name_len = len(name)
data = b"SELECT username FROM employees WHERE role = 'admin';"
data_len = len(data)
records.append(struct.pack(f"<BB{name_len}sH{data_len}s", status, name_len, name, data_len, data))

with open("fs_dump.bin", "wb") as f:
    f.write(b"DUMP")
    f.write(struct.pack("<H", len(records)))
    for r in records:
        f.write(r)
EOF
    python3 make_dump.py
    rm make_dump.py

    chown -R user:user /home/user/ticket_402
    chmod -R 777 /home/user
