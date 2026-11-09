#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git build-essential wget
    pip3 install pytest

    # Setup csv-parser
    mkdir -p /app/csv-parser-2.1.3
    wget -qO- https://github.com/vincentlaucsb/csv-parser/archive/refs/tags/2.1.3.tar.gz | tar xz --strip-components=1 -C /app/csv-parser-2.1.3 || true

    # Fallback if download fails
    mkdir -p /app/csv-parser-2.1.3/include
    touch /app/csv-parser-2.1.3/include/csv.hpp

    cat << 'EOF' > /app/csv-parser-2.1.3/dummy.cpp
int dummy_csv_parser() { return 0; }
EOF

    cat << 'EOF' > /app/csv-parser-2.1.3/Makefile
CXX ?= g++
CXXFLAGS = -O3 -Wall -std=c++98 -I./include

all: libcsvparser.a

libcsvparser.a: dummy.o
	ar rcs $@ $^

dummy.o: dummy.cpp
	$(CXX) $(CXXFLAGS) -c $< -o $@
EOF

    # Generate data corpora
    python3 -c "
import struct
import os

# Clean corpus
os.makedirs('/data/clean_corpus', exist_ok=True)
with open('/data/clean_corpus/metadata.csv', 'w') as f, open('/data/clean_corpus/embeddings.bin', 'wb') as b:
    f.write('id,expected_dim,offset,length\n')
    # id1: 3 dims, offset 0, length 12
    f.write('clean_1,3,0,12\n')
    b.write(struct.pack('<3f', 1.0, 2.0, 3.0))
    # id2: 2 dims, offset 12, length 8
    f.write('clean_2,2,12,8\n')
    b.write(struct.pack('<2f', 0.5, -0.5))

# Evil corpus
os.makedirs('/data/evil_corpus', exist_ok=True)
with open('/data/evil_corpus/metadata.csv', 'w') as f, open('/data/evil_corpus/embeddings.bin', 'wb') as b:
    f.write('id,expected_dim,offset,length\n')
    offset = 0

    # evil_1: length mismatch (length=16, expected_dim=5)
    f.write(f'evil_1,5,{offset},16\n')
    b.write(struct.pack('<4f', 1.0, 1.0, 1.0, 1.0)) # 16 bytes
    offset += 16

    # evil_2: contains NaN
    f.write(f'evil_2,2,{offset},8\n')
    b.write(struct.pack('<ff', float('nan'), 1.0))
    offset += 8

    # evil_3: contains Infinity
    f.write(f'evil_3,2,{offset},8\n')
    b.write(struct.pack('<ff', float('inf'), 1.0))
    offset += 8

    # evil_4: all zeros
    f.write(f'evil_4,3,{offset},12\n')
    b.write(struct.pack('<3f', 0.0, 0.0, 0.0))
    offset += 12
"

    # Setup workspace
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/workspace
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
    chmod -R 777 /data
