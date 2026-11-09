#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gdb strace sqlite3 g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # 1. Create the C++ source file
    cat << 'EOF' > /home/user/malware_src.cpp
#include <iostream>
#include <fstream>
#include <string>

void trigger_payload() {
    // Local variable to be found in GDB
    const char* decryption_key = "M4LW4R3_K3Y_99X";

    // File open to be caught by strace
    std::ifstream file_in("/home/user/target data copy.txt");

    // Deliberate segfault
    int* bad_ptr = nullptr;
    *bad_ptr = 42;
}

int main() {
    trigger_payload();
    return 0;
}
EOF

    # Compile with debug symbols and no optimization
    g++ -g -O0 /home/user/malware_src.cpp -o /home/user/malware_bin

    # Clean up source to hide the answer
    rm /home/user/malware_src.cpp

    # 2. Create the SQLite database with uncheckpointed WAL data
    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

# Connect and set WAL mode
conn = sqlite3.connect('/home/user/data.db')
conn.execute('PRAGMA journal_mode=WAL;')
conn.execute('CREATE TABLE exfiltrated_data (id INTEGER PRIMARY KEY, info TEXT);')

# Insert data (writes to WAL)
conn.execute("INSERT INTO exfiltrated_data (info) VALUES ('FLAG{W4L_R3C0V3R3D}');")
conn.commit()

# Force exit to prevent SQLite from checkpointing and deleting the WAL file on close
os._exit(0)
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    # Ensure proper permissions
    chown -R user:user /home/user/
    chmod -R 777 /home/user
