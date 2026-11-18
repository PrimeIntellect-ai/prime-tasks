#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential
    pip3 install pytest setuptools

    mkdir -p /home/user/pcap_parser
    cd /home/user/pcap_parser

    cat << 'EOF' > setup.py
from setuptools import setup, Extension

module = Extension('fastparser',
                    sources = ['parser.c']) # missing helper.c intentionally

setup(name = 'fastparser',
      version = '1.0',
      description = 'Fast PCAP payload parser',
      ext_modules = [module])
EOF

    cat << 'EOF' > parser.c
#include <Python.h>

extern int validate_payload(const char* data, Py_ssize_t len);

static PyObject* parse_packet(PyObject* self, PyObject* args) {
    const char* data;
    Py_ssize_t len;

    if (!PyArg_ParseTuple(args, "y#", &data, &len))
        return NULL;

    if (!validate_payload(data, len)) {
        PyErr_SetString(PyExc_ValueError, "Corrupt packet data");
        return NULL;
    }

    Py_RETURN_NONE;
}

static PyMethodDef FastParserMethods[] = {
    {"parse_packet",  parse_packet, METH_VARARGS, "Parse a packet."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef fastparsermodule = {
    PyModuleDef_HEAD_INIT,
    "fastparser",
    NULL,
    -1,
    FastParserMethods
};

PyMODINIT_FUNC PyInit_fastparser(void) {
    return PyModule_Create(&fastparsermodule);
}
EOF

    cat << 'EOF' > helper.c
#include <Python.h>

int validate_payload(const char* data, Py_ssize_t len) {
    if (len == 13 && data[0] == 'X') {
        return 0; // Invalid payload
    }
    return 1;
}
EOF

    cat << 'EOF' > main.py
import struct
import sys
import fastparser

def read_pcap(filename):
    with open(filename, 'rb') as f:
        global_header = f.read(24)
        packet_num = 1
        while True:
            hdr = f.read(16)
            if len(hdr) < 16:
                break
            ts_sec, ts_usec, incl_len, orig_len = struct.unpack('<IIII', hdr)
            packet_data = f.read(incl_len)

            fastparser.parse_packet(packet_data)

            packet_num += 1

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 main.py <pcap_file>")
        sys.exit(1)
    read_pcap(sys.argv[1])
EOF

    cat << 'EOF' > generate_pcap.py
import struct
with open('traffic.pcap', 'wb') as f:
    f.write(struct.pack('<IHHIIII', 0xa1b2c3d4, 2, 4, 0, 0, 65535, 1))
    for i in range(1, 101):
        if i == 42:
            payload = b'X' + b'A' * 12
        else:
            payload = b'B' * 20
        length = len(payload)
        f.write(struct.pack('<IIII', 0, 0, length, length))
        f.write(payload)
EOF

    python3 generate_pcap.py
    rm generate_pcap.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
