#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        python3-dev \
        gcc \
        build-essential \
        binutils \
        && rm -rf /var/lib/apt/lists/*

    pip3 install pytest grpcio grpcio-tools

    mkdir -p /app
    mkdir -p /home/user/broken_pr

    # Create legacy_filter source, compile and strip
    cat << 'EOF' > /app/legacy_filter.c
#include <stdio.h>
int main() {
    int c;
    while ((c = getchar()) != EOF) {
        putchar(~(c ^ 0x5A));
    }
    return 0;
}
EOF
    gcc -O2 /app/legacy_filter.c -o /app/legacy_filter
    strip /app/legacy_filter
    rm /app/legacy_filter.c

    # Create broken_pr files
    cat << 'EOF' > /home/user/broken_pr/setup.py
from setuptools import setup, Extension

module = Extension('filter_core', sources=['filter_core.c'])

setup(
    name='filter_grpc',
    version='1.0',
    ext_modules=[module]
)
EOF

    cat << 'EOF' > /home/user/broken_pr/filter_core.c
#include <Python.h>

static PyObject* filter_process(PyObject* self, PyObject* args) {
    const char* input;
    Py_ssize_t len;
    if (!PyArg_ParseTuple(args, "y#", &input, &len)) {
        return NULL;
    }

    char* output = PyMem_Malloc(len);
    if (!output) return PyErr_NoMemory();

    for (Py_ssize_t i = 0; i < len; i++) {
        output[i] = input[i] + 1; // BROKEN LOGIC
    }

    PyObject* ret = PyBytes_FromStringAndSize(output, len);
    PyMem_Free(output);
    return ret;
}

static PyMethodDef FilterMethods[] = {
    {"process", filter_process, METH_VARARGS, "Process data"},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef filtermodule = {
    PyModuleDef_HEAD_INIT,
    "filter_core",
    NULL,
    -1,
    FilterMethods
};

PyMODINIT_FUNC PyInit_filter_core(void) {
    return PyModule_Create(&filtermodule);
}
EOF

    cat << 'EOF' > /home/user/broken_pr/service.proto
syntax = "proto3";

service FilterService {
  rpc ProcessData (DataRequest) returns (DataResponse) {}
}

message DataRequest {
  bytes data = 1;
}

message DataResponse {
  bytes data = 1;
}
EOF

    cat << 'EOF' > /home/user/broken_pr/server.py
import grpc
from concurrent import futures
import service_pb2
import service_pb2_grpc
import filter_core

class FilterServiceServicer(service_pb2_grpc.FilterServiceServicer):
    def ProcessData(self, request, context):
        processed = filter_core.process(request.data)
        return service_pb2.DataResponse(data=processed)

def serve():
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    service_pb2_grpc.add_FilterServiceServicer_to_server(FilterServiceServicer(), server)
    server.add_insecure_port('[::]:50051')
    server.start()
    server.wait_for_termination()

if __name__ == '__main__':
    serve()
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
