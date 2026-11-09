#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip cmake build-essential
pip3 install pytest

mkdir -p /home/user/migration/src
mkdir -p /home/user/migration/data

# 1. Create dependency file
cat << 'EOF' > /home/user/migration/deps.txt
data_B.txt depends on data_A.txt
data_C.txt depends on data_B.txt
data_D.txt depends on data_A.txt
data_E.txt depends on data_D.txt
data_F.txt depends on data_C.txt
data_F.txt depends on data_E.txt
EOF

# 2. Create raw data files
echo "AAAA" > /home/user/migration/data_A.txt
echo "BBBB" > /home/user/migration/data_B.txt
echo "CCCC" > /home/user/migration/data_C.txt
echo "DDDD" > /home/user/migration/data_D.txt
echo "EEEE" > /home/user/migration/data_E.txt
echo "FFFF" > /home/user/migration/data_F.txt

# Expected concatenated output (each byte incremented by 1 by the C library)
cat << 'EOF' > /home/user/migration/expected_output.txt
BBBB
CCCC
DDDD
EEEE
FFFF
GGGG
EOF

# 3. Create CMake C library
cat << 'EOF' > /home/user/migration/src/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(processor)
add_library(processor SHARED processor.c)
EOF

cat << 'EOF' > /home/user/migration/src/processor.c
void process_buffer(char* buffer, int length) {
    for (int i = 0; i < length; i++) {
        if (buffer[i] >= 'A' && buffer[i] <= 'Z') {
            buffer[i] = buffer[i] + 1;
        }
    }
}
EOF

# 4. Create the broken Python 2 processing script
cat << 'EOF' > /home/user/migration/process.py
import sys
import ctypes
import os

# Broken path & syntax
lib = ctypes.CDLL('./libprocessor.so')

def process_file(filepath):
    print "Processing", filepath
    with open(filepath, 'r') as f:
        data = f.read().strip()

    buf = ctypes.create_string_buffer(data.encode('ascii'))

    # Broken python 2 loop syntax check
    for i in xrange(1):
        lib.process_buffer(buf, len(data))

    with open(filepath + ".out", 'w') as f:
        f.write(buf.value.decode('ascii') + '\n')
    print "Done"

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print "Need file"
        sys.exit(1)
    process_file(sys.argv[1])
EOF
chmod +x /home/user/migration/process.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
