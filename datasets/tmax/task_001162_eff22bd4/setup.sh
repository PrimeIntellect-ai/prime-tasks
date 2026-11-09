#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev gcc strace
    pip3 install pytest setuptools

    mkdir -p /app/eval_corpus/evil
    mkdir -p /app/eval_corpus/clean
    mkdir -p /home/user/audioproc

    # Create Python script to generate WAV files
    cat << 'EOF' > /tmp/gen_wav.py
import struct
import os

def create_wav(path, is_evil):
    fmt_chunk = b'fmt \x10\x00\x00\x00\x01\x00\x01\x00\x44\xac\x00\x00\x88\x58\x01\x00\x02\x00\x10\x00'
    data_chunk = b'data\x08\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00'

    if is_evil:
        junk_chunk = b'JUNK\x04\x00\x00\x00\xde\xad\xbe\xef'
        chunks = fmt_chunk + junk_chunk + data_chunk
    else:
        chunks = fmt_chunk + data_chunk

    file_size = 4 + len(chunks)

    with open(path, 'wb') as f:
        f.write(b'RIFF')
        f.write(struct.pack('<I', file_size))
        f.write(b'WAVE')
        f.write(chunks)

create_wav('/app/trigger.wav', True)
for i in range(5):
    create_wav(f'/app/eval_corpus/evil/file_{i}.wav', True)
    create_wav(f'/app/eval_corpus/clean/file_{i}.wav', False)
EOF

    python3 /tmp/gen_wav.py
    rm /tmp/gen_wav.py

    # Create setup.py with bug
    cat << 'EOF' > /home/user/audioproc/setup.py
from setuptools import setup, Extension

module = Extension('fast_wav', sources=['fast_wave.c'])

setup(
    name='fast_wav',
    version='1.0',
    ext_modules=[module]
)
EOF

    # Create fast_wav.c
    cat << 'EOF' > /home/user/audioproc/fast_wav.c
#include <Python.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static PyObject* parse_wav(PyObject* self, PyObject* args) {
    const char* filepath;
    if (!PyArg_ParseTuple(args, "s", &filepath)) {
        return NULL;
    }

    FILE *f = fopen(filepath, "rb");
    if (!f) Py_RETURN_NONE;

    char buf[4];
    if (fread(buf, 1, 4, f) != 4) { fclose(f); Py_RETURN_NONE; } // RIFF
    fseek(f, 4, SEEK_CUR); // size
    if (fread(buf, 1, 4, f) != 4) { fclose(f); Py_RETURN_NONE; } // WAVE

    while (fread(buf, 1, 4, f) == 4) {
        unsigned int chunk_size;
        if (fread(&chunk_size, 4, 1, f) != 1) break;
        if (strncmp(buf, "JUNK", 4) == 0) {
            char *junk_data = malloc(chunk_size);
            if (junk_data) {
                fread(junk_data, 1, chunk_size, f);
                // LEAK: intentionally not freeing junk_data
            }
        } else {
            fseek(f, chunk_size, SEEK_CUR);
        }
    }
    fclose(f);
    Py_RETURN_NONE;
}

static PyMethodDef FastWavMethods[] = {
    {"parse_wav", parse_wav, METH_VARARGS, "Parse a WAV file."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef fastwavmodule = {
    PyModuleDef_HEAD_INIT,
    "fast_wav",
    NULL,
    -1,
    FastWavMethods
};

PyMODINIT_FUNC PyInit_fast_wav(void) {
    return PyModule_Create(&fastwavmodule);
}
EOF

    # Create run_service.py
    cat << 'EOF' > /home/user/audioproc/run_service.py
import sys

def run():
    if len(sys.argv) < 2:
        print("Usage: python3 run_service.py <path_to_wav>")
        sys.exit(1)

    try:
        import fast_wav
    except ImportError:
        print("Failed to import fast_wav. Did you build it?")
        sys.exit(1)

    for _ in range(100):
        fast_wav.parse_wav(sys.argv[1])

    print("Processed successfully.")

if __name__ == "__main__":
    run()
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/audioproc
    chmod -R 777 /home/user
    chmod -R 777 /app
