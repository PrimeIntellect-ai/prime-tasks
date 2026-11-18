#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential sqlite3
    pip3 install pytest setuptools

    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/app/fast_parser.c
#include <Python.h>
#include <string.h>

static PyObject* parse(PyObject* self, PyObject* args) {
    const char* input;
    char buffer[100];
    if (!PyArg_ParseTuple(args, "s", &input)) {
        return NULL;
    }
    // Buffer overflow vulnerability
    strcpy(buffer, input);
    return Py_BuildValue("i", strlen(buffer));
}

static PyMethodDef FastParserMethods[] = {
    {"parse", parse, METH_VARARGS, "Parse a string."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef fast_parsermodule = {
    PyModuleDef_HEAD_INIT, "fast_parser", NULL, -1, FastParserMethods
};

PyMODINIT_FUNC PyInit_fast_parser(void) {
    return PyModule_Create(&fast_parsermodule);
}
EOF

    cat << 'EOF' > /home/user/app/setup.py
from setuptools import setup, Extension

module1 = Extension('fast_parser',
                    source = ['fast_parser.c'] # Intentional bug: should be 'sources'
                    )

setup (name = 'FastParser',
       version = '1.0',
       description = 'This is a demo package',
       ext_modules = [module1])
EOF

    cat << 'EOF' > /home/user/app/inputs.txt
short_line_1
short_line_2
this_is_a_normal_length_line
this_is_a_very_long_line_that_exceeds_one_hundred_characters_in_length_and_will_cause_a_segmentation_fault_when_copied_into_the_buffer_due_to_strcpy
another_short_line
EOF

    sqlite3 /home/user/app/data.db "CREATE TABLE events (id INTEGER PRIMARY KEY, name TEXT);"
    for i in $(seq 1 42); do
        sqlite3 /home/user/app/data.db "INSERT INTO events (name) VALUES ('event_$i');"
    done

    # Corrupt the SQLite database header
    dd if=/dev/zero of=/home/user/app/data.db bs=1 count=16 conv=notrunc

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
