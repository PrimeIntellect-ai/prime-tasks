#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/src /home/user/lib

    cat << 'EOF' > /home/user/src/data_processor.c
#include <stdint.h>

struct Record {
    uint8_t type;
    double value;
    uint32_t id;
} __attribute__((packed));

int get_record_size() {
    return sizeof(struct Record);
}

void process_record(struct Record* r) {
    r->value *= 2.0;
    r->id += 1;
}
EOF

    gcc -shared -fPIC -o /home/user/lib/libdata_processor.so /home/user/src/data_processor.c

    cat << 'EOF' > /home/user/test_processor.py
import ctypes
import unittest

lib = ctypes.CDLL('/home/user/lib/libdata_processor.so')

class Record(ctypes.Structure):
    _fields_ = [
        ("type", ctypes.c_uint8),
        ("value", ctypes.c_double),
        ("id", ctypes.c_uint32)
    ]

lib.get_record_size.restype = ctypes.c_int
lib.process_record.argtypes = [ctypes.POINTER(Record)]

class TestDataProcessor(unittest.TestCase):
    def test_abi_size(self):
        c_size = lib.get_record_size()
        py_size = ctypes.sizeof(Record)
        self.assertEqual(c_size, py_size, f"ABI size mismatch! C expected {c_size}, Python provided {py_size}")

    def test_processing(self):
        r = Record(type=1, value=5.0, id=100)
        lib.process_record(ctypes.byref(r))
        self.assertAlmostEqual(r.value, 10.0)
        self.assertEqual(r.id, 101)

if __name__ == '__main__':
    unittest.main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
