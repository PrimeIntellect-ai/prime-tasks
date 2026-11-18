#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential
    pip3 install --no-cache-dir pytest grpcio grpcio-tools websockets setuptools

    mkdir -p /home/user/sec_ws/src
    mkdir -p /home/user/sec_ws/proto

    cat << 'EOF' > /home/user/sec_ws/proto/auth.proto
syntax = "proto3";
message AuthToken {
    string username = 1;
    string role = 2;
    int32 expiration = 3;
}
EOF

    cat << 'EOF' > /home/user/sec_ws/setup.py
from setuptools import setup, Extension

# Bug: module name mismatch and missing include for Python.h (implicitly handled by setuptools if name is right, but the name is wrong here)
# The C file defines PyInit_fast_auth, but setup.py defines fast_auth_ext
fast_auth_module = Extension('fast_auth_ext',
                    sources = ['src/deserializer.c'])

setup(name = 'fast_auth',
      version = '1.0',
      description = 'Fast deserializer for auth tokens',
      ext_modules = [fast_auth_module])
EOF

    cat << 'EOF' > /home/user/sec_ws/src/deserializer.c
#include <Python.h>
#include <stdint.h>
#include <string.h>

static PyObject* parse_token(PyObject* self, PyObject* args) {
    PyObject* bytes_obj;
    if (!PyArg_ParseTuple(args, "O", &bytes_obj)) {
        return NULL;
    }

    if (!PyBytes_Check(bytes_obj)) {
        PyErr_SetString(PyExc_TypeError, "Expected bytes");
        return NULL;
    }

    Py_ssize_t size = PyBytes_Size(bytes_obj);
    if (size < 2) {
        PyErr_SetString(PyExc_ValueError, "Payload too short");
        return NULL;
    }

    const char* data = PyBytes_AsString(bytes_obj);

    // First 2 bytes represent the length of the protobuf payload
    uint16_t msg_len = (uint8_t)data[0] << 8 | (uint8_t)data[1];

    // BUG: No bounds checking against 'size'.
    // If msg_len > size - 2, we read out of bounds.

    char* msg_body = (char*)malloc(msg_len);
    if (!msg_body) return PyErr_NoMemory();

    // Trigger Out-of-bounds read / segfault
    memcpy(msg_body, data + 2, msg_len);

    PyObject* result = PyBytes_FromStringAndSize(msg_body, msg_len);
    free(msg_body);

    return result;
}

static PyMethodDef FastAuthMethods[] = {
    {"parse_token",  parse_token, METH_VARARGS, "Parse a binary auth token."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef fastauthmodule = {
    PyModuleDef_HEAD_INIT,
    "fast_auth",
    NULL,
    -1,
    FastAuthMethods
};

PyMODINIT_FUNC PyInit_fast_auth(void) {
    return PyModule_Create(&fastauthmodule);
}
EOF

    cat << 'EOF' > /home/user/sec_ws/test_server.py
import asyncio
import websockets
import threading
import time
import struct
import sys

# Import generated protobuf and our C extension
try:
    import auth_pb2
except ImportError:
    print("FAILED: auth_pb2 not found. Did you compile the protobuf?")
    sys.exit(1)

try:
    import fast_auth
except ImportError as e:
    print(f"FAILED: fast_auth module failed to load: {e}")
    sys.exit(1)

async def handler(websocket, path):
    try:
        async for message in websocket:
            try:
                # Use C extension to parse length-prefixed bytes
                proto_bytes = fast_auth.parse_token(message)
                token = auth_pb2.AuthToken()
                token.ParseFromString(proto_bytes)
                await websocket.send(f"Welcome {token.username}")
            except ValueError as e:
                await websocket.send(f"Error: {str(e)}")
            except Exception as e:
                await websocket.send(f"Unknown Error")
    except websockets.exceptions.ConnectionClosed:
        pass

async def serve():
    async with websockets.serve(handler, "localhost", 8765):
        await asyncio.Future()  # run forever

def start_server():
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    loop.run_until_complete(serve())

server_thread = threading.Thread(target=start_server, daemon=True)
server_thread.start()
time.sleep(1) # Wait for server to start

async def run_tests():
    async with websockets.connect("ws://localhost:8765") as ws:
        # Test 1: Valid payload
        token = auth_pb2.AuthToken(username="admin", role="admin", expiration=3600)
        tb = token.SerializeToString()
        payload = struct.pack(">H", len(tb)) + tb
        await ws.send(payload)
        resp = await ws.recv()
        if resp != "Welcome admin":
            print("FAILED: Valid token test failed.")
            sys.exit(1)

        # Test 2: Malicious payload (buffer overflow attempt)
        # Claims length 60000, but actual payload is 5 bytes
        malicious_payload = struct.pack(">H", 60000) + b"12345"
        await ws.send(malicious_payload)
        resp = await ws.recv()
        if "Invalid token length" not in resp:
            print("FAILED: Did not receive expected ValueError for invalid length.")
            sys.exit(1)

    print("SUCCESS_HASH_8F92A1B")

asyncio.get_event_loop().run_until_complete(run_tests())
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
