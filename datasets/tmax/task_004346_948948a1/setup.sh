#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential
    pip3 install pytest scapy

    mkdir -p /app/vendored_parser/src
    mkdir -p /app/corpora/evil
    mkdir -p /app/corpora/clean

    cat << 'EOF' > /app/vendored_parser/src/parser.c
#include <Python.h>
#include <string.h>

static PyObject* parse_packet(PyObject* self, PyObject* args) {
    const char* data;
    Py_ssize_t length;

    if (!PyArg_ParseTuple(args, "y#", &data, &length)) {
        return NULL;
    }

    if (length < 16) {
        PyErr_SetString(PyExc_ValueError, "Packet too short");
        return NULL;
    }

    double lat, lon;
    memcpy(&lat, data, sizeof(double));
    memcpy(&lon, data + sizeof(double), sizeof(double));

    PyObject* dict = PyDict_New();
    if (!dict) return NULL;

    /* Intentional bug: precision loss */
    PyDict_SetItemString(dict, "lat", PyFloat_FromDouble((float)lat));
    PyDict_SetItemString(dict, "lon", PyFloat_FromDouble((float)lon));

    return dict;
}

static PyMethodDef ParserMethods[] = {
    {"parse_packet", parse_packet, METH_VARARGS, "Parse C2 telemetry packet."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef parsermodule = {
    PyModuleDef_HEAD_INIT,
    "c2_telemetry_parser",
    NULL,
    -1,
    ParserMethods
};

PyMODINIT_FUNC PyInit_c2_telemetry_parser(void) {
    return PyModule_Create(&parsermodule);
}
EOF

    cat << 'EOF' > /app/vendored_parser/setup.py
from setuptools import setup, Extension

module1 = Extension('c2_telemetry_parser',
                    sources = ['src/parser.c'])

setup (name = 'c2_telemetry_parser',
       version = '1.0.0',
       description = 'C2 Telemetry Parser',
       ext_modules = [module1])
EOF

    cat << 'EOF' > /app/vendored_parser/Makefile
all:
	python3 setup.py build

install:
	python3 setup.py install
EOF

    cd /app/vendored_parser
    make install

    cat << 'EOF' > /tmp/generate_pcaps.py
from scapy.all import wrpcap, Ether, IP, UDP
import struct
import math
import os

lat_evil = 1000.0
lon_evil = math.sqrt(1337.0**2 - lat_evil**2)

lat_clean = 1000.0
lon_clean = 887.45084

def make_pcap(filename, lat, lon):
    payload = struct.pack("dd", lat, lon)
    pkt = Ether()/IP(dst="127.0.0.1")/UDP(dport=1234)/payload
    wrpcap(filename, [pkt])

for i in range(5):
    make_pcap(f"/app/corpora/evil/evil_{i}.pcap", lat_evil, lon_evil)
    make_pcap(f"/app/corpora/clean/clean_{i}.pcap", lat_clean, lon_clean)
EOF

    python3 /tmp/generate_pcaps.py
    rm /tmp/generate_pcaps.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
