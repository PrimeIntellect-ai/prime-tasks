#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ cmake python3-dev python3-setuptools
    pip3 install pytest

    mkdir -p /app/proprietary /app/fastalgo/src

    cat << 'EOF' > /app/proprietary/algo.cpp
extern "C" int process_data_impl(int val) { return val * val; }
EOF
    g++ -shared -fPIC -o /app/proprietary/libalgo.so /app/proprietary/algo.cpp

    cat << 'EOF' > /app/fastalgo/setup.py
from setuptools import setup, Extension
from setuptools.command.build_ext import build_ext
import subprocess, os

class CMakeBuild(build_ext):
    def run(self):
        for ext in self.extensions:
            self.build_extension(ext)

    def build_extension(self, ext):
        extdir = os.path.abspath(os.path.dirname(self.get_ext_fullpath(ext.name)))
        subprocess.check_call(['cmake', ext.sourcedir, '-DCMAKE_LIBRARY_OUTPUT_DIRECTORY=' + extdir])
        subprocess.check_call(['cmake', '--build', '.'])

class CMakeExtension(Extension):
    def __init__(self, name, sourcedir=''):
        Extension.__init__(self, name, sources=[])
        self.sourcedir = os.path.abspath(sourcedir)

setup(name='fastalgo', version='1.0', ext_modules=[CMakeExtension('fastalgo')], cmdclass=dict(build_ext=CMakeBuild))
EOF

    cat << 'EOF' > /app/fastalgo/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(fastalgo)
find_package(Python3 COMPONENTS Development REQUIRED)
# DELIBERATE PERTURBATION: Missing link_directories and link libraries
add_library(fastalgo MODULE src/wrapper.c)
target_include_directories(fastalgo PRIVATE ${Python3_INCLUDE_DIRS})
set_target_properties(fastalgo PROPERTIES PREFIX "" SUFFIX ".so")
EOF

    cat << 'EOF' > /app/fastalgo/src/wrapper.c
#include <Python.h>
extern int process_data_impl(int);

static PyObject* process_data(PyObject* self, PyObject* args) {
    int input;
    if (!PyArg_ParseTuple(args, "i", &input)) return NULL;
    int result = process_data_impl(input);
    return Py_BuildValue("i", result);
}

static PyMethodDef FastAlgoMethods[] = {
    {"process_data",  process_data, METH_VARARGS, "Process data."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef fastalgomodule = {
    PyModuleDef_HEAD_INIT, "fastalgo", NULL, -1, FastAlgoMethods
};

PyMODINIT_FUNC PyInit_fastalgo(void) {
    return PyModule_Create(&fastalgomodule);
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
