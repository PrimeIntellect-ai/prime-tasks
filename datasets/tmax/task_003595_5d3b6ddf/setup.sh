#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make binutils
pip3 install pytest

mkdir -p /home/user/legacy
mkdir -p /app/corpora/clean
mkdir -p /app/corpora/evil

# Generate fast_tlv.c
cat << 'EOF' > /home/user/legacy/fast_tlv.c
#include <Python.h>
#include <string.h>

static PyObject* fast_tlv_parse(PyObject* self, PyObject* args) {
    const char* data;
    int data_len;
    if (!PyArg_ParseTuple(args, "s#", &data, &data_len)) {
        return NULL;
    }

    // Buggy implementation stub
    char buf[256];
    if (data_len > 4 && memcmp(data, "TLV1", 4) == 0) {
        int offset = 4;
        while (offset + 3 <= data_len) {
            unsigned char type = data[offset];
            unsigned short length = (unsigned char)data[offset+1] | ((unsigned char)data[offset+2] << 8);
            offset += 3;

            if (type == 0xFF) {
                length -= 1; // Integer underflow bug
            }

            if (length > 0 && offset + length <= data_len) {
                memcpy(buf, data + offset, length); // Buffer overflow bug
                offset += length;
            } else if (length == 0) {
                // Null pointer / bad advance bug
                offset += 1;
            } else {
                break;
            }
        }
    }

    Py_RETURN_NONE;
}

static PyMethodDef FastTlvMethods[] = {
    {"parse",  fast_tlv_parse, METH_VARARGS, "Parse TLV data."},
    {NULL, NULL, 0, NULL}
};

PyMODINIT_FUNC initfast_tlv(void) {
    (void) Py_InitModule("fast_tlv", FastTlvMethods);
}
EOF

# Generate oracle_parser
cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    FILE* f = fopen(argv[1], "rb");
    if (!f) return 1;

    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);

    char* data = malloc(size);
    fread(data, 1, size, f);
    fclose(f);

    char buf[256];
    if (size > 4 && memcmp(data, "TLV1", 4) == 0) {
        int offset = 4;
        while (offset + 3 <= size) {
            unsigned char type = data[offset];
            unsigned short length = (unsigned char)data[offset+1] | ((unsigned char)data[offset+2] << 8);
            offset += 3;

            if (type == 0xFF) {
                length -= 1;
            }

            if (length > 0 && offset + length <= size) {
                memcpy(buf, data + offset, length);
                offset += length;
            } else if (length == 0) {
                offset += 1;
            } else {
                break;
            }
        }
    }

    free(data);
    return 0;
}
EOF
gcc /tmp/oracle.c -o /app/oracle_parser
strip /app/oracle_parser

# Generate corpora
python3 -c '
import os
import struct

clean_dir = "/app/corpora/clean"
evil_dir = "/app/corpora/evil"

for i in range(100):
    with open(os.path.join(clean_dir, f"clean_{i}.bin"), "wb") as f:
        f.write(b"TLV1")
        f.write(struct.pack("<BH", 1, 10))
        f.write(b"A" * 10)

for i in range(20):
    with open(os.path.join(evil_dir, f"evil_stack_{i}.bin"), "wb") as f:
        f.write(b"TLV1")
        f.write(struct.pack("<BH", 1, 300))
        f.write(b"A" * 300)

for i in range(15):
    with open(os.path.join(evil_dir, f"evil_int_{i}.bin"), "wb") as f:
        f.write(b"TLV1")
        f.write(struct.pack("<BH", 0xFF, 10))
        f.write(b"A" * 10)

for i in range(15):
    with open(os.path.join(evil_dir, f"evil_null_{i}.bin"), "wb") as f:
        f.write(b"TLV1")
        f.write(struct.pack("<BH", 1, 0))
'

# Generate benchmark.py
cat << 'EOF' > /home/user/benchmark.py
import time
import sys

def run_benchmark():
    try:
        import fast_tlv
    except ImportError:
        print("fast_tlv not built yet")
        sys.exit(0)

    data = b"TLV1" + (b"\x01\x0A\x00" + b"A"*10) * 100000
    start = time.time()
    fast_tlv.parse(data)
    end = time.time()

    assert end - start < 0.5, f"Benchmark failed: took {end - start}s"
    print("Benchmark passed!")

if __name__ == "__main__":
    run_benchmark()
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
