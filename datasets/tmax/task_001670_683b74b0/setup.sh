#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ ffmpeg
    pip3 install pytest

    mkdir -p /app/src /app/bin /app/corpus/clean /app/corpus/evil

    # Generate test video
    ffmpeg -f lavfi -i color=c=black:s=320x240:r=30:d=4 -c:v libx264 /app/debug_run.mp4

    # Create metadata.wal
    cat << 'EOF' > /app/metadata.wal
0.033333 QUERY_START
1.000000 INDEX_SCAN
EOF

    # Create db_parser.cpp
    cat << 'EOF' > /app/src/db_parser.cpp
#include <iostream>
#include <fstream>
#include <string>

void parse_wal_entry(std::string entry) {
    std::cout << entry << std::endl;
    parse_wal_entry(entry); // Infinite recursion
}

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    std::ifstream file(argv[1]);
    std::string line;
    int i = 0;
    while (std::getline(file, line)) {
        if (i < 5) {
            // Missing i++
        }
        parse_wal_entry(line);
    }
    return 0;
}
EOF

    # Create filter.cpp skeleton
    cat << 'EOF' > /app/src/filter.cpp
#include <iostream>
int main(int argc, char** argv) {
    return 0;
}
EOF

    # Create clean corpus
    cat << 'EOF' > /app/corpus/clean/log1.txt
SEQ: 1
SELECT * FROM users;
SEQ: 2
UPDATE users SET name='test';
EOF

    # Create evil corpus
    cat << 'EOF' > /app/corpus/evil/log1.txt
SEQ: 1
DROP TABLE users;
EOF

    cat << 'EOF' > /app/corpus/evil/log2.txt
SEQ: 2
SELECT * FROM test;
SEQ: 1
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
