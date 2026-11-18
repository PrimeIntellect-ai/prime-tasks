#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential
    pip3 install pytest numpy scipy pandas setuptools

    # Create app directory and generate audio data
    mkdir -p /app
    cat << 'EOF' > /tmp/gen_audio.py
import numpy as np
import scipy.io.wavfile as wav
import os

os.makedirs("/app", exist_ok=True)
np.random.seed(42)
data = np.random.randint(-32768, 32767, 44100 * 10, dtype=np.int16)
wav.write("/app/audio_data.wav", 44100, data)
EOF
    python3 /tmp/gen_audio.py
    rm /tmp/gen_audio.py

    # Create pipeline directory
    mkdir -p /home/user/audio_pipeline

    # Create setup.py
    cat << 'EOF' > /home/user/audio_pipeline/setup.py
from setuptools import setup, Extension
import numpy

module1 = Extension('cext_energy',
                    sources = ['energy.c'],
                    include_dirs=[numpy.get_include()])

setup(name = 'cext_energy',
      version = '1.0',
      description = 'Compute energy',
      ext_modules = [module1])
EOF

    # Create energy.c
    cat << 'EOF' > /home/user/audio_pipeline/energy.c
#include <Python.h>
#include <numpy/arrayobject.h>

static PyObject* compute_energy(PyObject* self, PyObject* args) {
    PyArrayObject *input_array;
    int window_size;

    if (!PyArg_ParseTuple(args, "O!i", &PyArray_Type, &input_array, &window_size)) {
        return NULL;
    }

    int16_t *data = (int16_t *)PyArray_DATA(input_array);
    npy_intp num_samples = PyArray_SIZE(input_array);
    npy_intp num_windows = num_samples / window_size;

    npy_intp dims[1] = {num_windows};
    PyArrayObject *out_array = (PyArrayObject *)PyArray_SimpleNew(1, dims, NPY_DOUBLE);
    double *out_data = (double *)PyArray_DATA(out_array);

    for (int i = 0; i < num_windows; i++) {
        // BUG: signed 32-bit int overflows when summing 4096 squares of 16-bit PCM values
        int sum = 0; 
        for (int j = 0; j < window_size; j++) {
            int16_t val = data[i * window_size + j];
            // BUG: Build error - undefined variable 'val2' instead of 'val'
            sum += val2 * val;
        }
        out_data[i] = (double)sum;
    }

    return PyArray_Return(out_array);
}

static PyMethodDef EnergyMethods[] = {
    {"compute_energy",  compute_energy, METH_VARARGS, "Compute energy of windows."},
    {NULL, NULL, 0, NULL}        /* Sentinel */
};

static struct PyModuleDef energy_module = {
    PyModuleDef_HEAD_INIT,
    "cext_energy",   /* name of module */
    NULL, /* module documentation, may be NULL */
    -1,       /* size of per-interpreter state of the module,
                 or -1 if the module keeps state in global variables. */
    EnergyMethods
};

PyMODINIT_FUNC PyInit_cext_energy(void) {
    import_array();
    return PyModule_Create(&energy_module);
}
EOF

    # Create process.py
    cat << 'EOF' > /home/user/audio_pipeline/process.py
import sys
import numpy as np
import scipy.io.wavfile as wav
import cext_energy

def main():
    if len(sys.argv) != 4:
        print("Usage: process.py <input.wav> <window_size> <output.csv>")
        sys.exit(1)

    in_file = sys.argv[1]
    window_size = int(sys.argv[2])
    out_file = sys.argv[3]

    sr, data = wav.read(in_file)
    if data.dtype != np.int16:
        raise ValueError("Must be 16-bit PCM")

    energies = cext_energy.compute_energy(data, window_size)
    np.savetxt(out_file, energies, delimiter=",", fmt="%.5f")

if __name__ == "__main__":
    main()
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
