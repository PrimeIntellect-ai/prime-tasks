#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev gcc build-essential
    pip3 install pytest websockets setuptools

    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/app/processor.c
#include <Python.h>
#include <string.h>
#include <stdlib.h>

static PyObject* processor_reverse(PyObject* self, PyObject* args) {
    const char* input_str;
    if (!PyArg_ParseTuple(args, "s", &input_str)) {
        return NULL;
    }

    // Vulnerable fixed-size buffer
    char buffer[50];
    strcpy(buffer, input_str); // Buffer overflow if input_str >= 50 chars

    int len = strlen(buffer);
    for (int i = 0; i < len / 2; i++) {
        char temp = buffer[i];
        buffer[i] = buffer[len - 1 - i];
        buffer[len - 1 - i] = temp;
    }

    return Py_BuildValue("s", buffer);
}

static PyMethodDef ProcessorMethods[] = {
    {"reverse",  processor_reverse, METH_VARARGS, "Reverse a string."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef processormodule = {
    PyModuleDef_HEAD_INIT, "processor", NULL, -1, ProcessorMethods
};

PyMODINIT_FUNC PyInit_processor(void) {
    return PyModule_Create(&processormodule);
}
EOF

    cat << 'EOF' > /home/user/app/setup.py
from setuptools import setup, Extension

module1 = Extension('processor', sources=['processor.c'])

setup(name='ProcessorPackage',
      version='1.0',
      description='String processing package',
      ext_modules=[module1])
EOF

    cat << 'EOF' > /home/user/app/server.py
import asyncio
import websockets
import json
import processor

async def handler(websocket, path):
    async for message in websocket:
        try:
            data = json.loads(message)
            if data.get("action") == "reverse":
                text = data.get("text", "")
                reversed_text = processor.reverse(text)
                await websocket.send(json.dumps({"status": "ok", "result": reversed_text}))
            else:
                await websocket.send(json.dumps({"status": "error", "message": "Unknown action"}))
        except Exception as e:
            await websocket.send(json.dumps({"status": "error", "message": str(e)}))

start_server = websockets.serve(handler, "localhost", 8765)
asyncio.get_event_loop().run_until_complete(start_server)
asyncio.get_event_loop().run_forever()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
