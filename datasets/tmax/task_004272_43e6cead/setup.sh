#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential sqlite3
pip3 install pytest

mkdir -p /app/c_src

cat << 'EOF' > /app/generate.py
import os
import sqlite3
import wave
import struct
import math

os.makedirs('/app/c_src', exist_ok=True)

sample_rate = 8000
num_samples = 8000 * 5
audio_path = '/app/data.wav'

with wave.open(audio_path, 'w') as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(sample_rate)

    for i in range(num_samples):
        val = int(10000 * math.sin(2 * math.pi * 440 * i / sample_rate))
        f.writeframes(struct.pack('h', val))

db_path = '/app/events.db'
conn = sqlite3.connect(db_path)
c = conn.cursor()
c.execute('CREATE TABLE events (event_id INTEGER PRIMARY KEY, start_sample INTEGER, end_sample INTEGER)')
c.execute('CREATE TABLE metadata (event_id INTEGER, description TEXT)')

events = [
    (1, 0, 1000),
    (2, 1000, 2500),
    (3, 4000, 4010),
    (4, 5000, 8000)
]
for e in events:
    c.execute('INSERT INTO events VALUES (?, ?, ?)', e)
    c.execute('INSERT INTO metadata VALUES (?, ?)', (e[0], 'meta1'))
    c.execute('INSERT INTO metadata VALUES (?, ?)', (e[0], 'meta2'))

conn.commit()
conn.close()

with open('/app/setup.py', 'w') as f:
    f.write("""from setuptools import setup, Extension
module = Extension('fast_audio', sources=['c_src/filter.c'])
setup(name='fast_audio', version='1.0', ext_modules=[module])
""")

with open('/app/c_src/filter.c', 'w') as f:
    f.write("""#define PY_SSIZE_T_CLEAN
#include <Python.h>
#include <math.h>

static PyObject* calculate_power(PyObject* self, PyObject* args) {
    PyObject* list_obj;
    if (!PyArg_ParseTuple(args, "O", &list_obj)) return NULL;

    Py_ssize_t size = PyList_Size(list_obj);
    double sum = 0.0;

    // BUG 1: Buffer overflow (i <= size instead of i < size)
    // BUG 2: Incorrect RMS formula (just sum instead of sum of squares)
    for (Py_ssize_t i = 0; i <= size; i++) {
        PyObject* item = PyList_GetItem(list_obj, i);
        if (!item) continue;
        double val = PyFloat_AsDouble(item);
        sum += val; // Should be val * val
    }

    // BUG 2 part 2: Should be sqrt(sum / size)
    double result = sum / size; 

    return PyFloat_FromDouble(result);
}

static PyMethodDef FastAudioMethods[] = {
    {"calculate_power", calculate_power, METH_VARARGS, "Calculate RMS power"},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef fastaudiomodule = {
    PyModuleDef_HEAD_INIT, "fast_audio", NULL, -1, FastAudioMethods
};

PyMODINIT_FUNC PyInit_fast_audio(void) {
    return PyModule_Create(&fastaudiomodule);
}
""")

with open('/app/processor.py', 'w') as f:
    f.write("""import sqlite3
import wave
import struct
import json
import fast_audio

def run():
    conn = sqlite3.connect('/app/events.db')
    c = conn.cursor()
    # BUG: Cross join without distinct causes duplicate processing
    c.execute('SELECT events.event_id, start_sample, end_sample FROM events JOIN metadata')
    rows = c.fetchall()

    wav = wave.open('/app/data.wav', 'r')
    frames = wav.readframes(wav.getnframes())
    samples = struct.unpack(f"{len(frames)//2}h", frames)

    results = {}
    for row in rows:
        eid, start, end = row
        chunk = [float(x) for x in samples[start:end]]
        if chunk:
            power = fast_audio.calculate_power(chunk)
            results[str(eid)] = power

    with open('/app/output.json', 'w') as f:
        json.dump(results, f)

if __name__ == '__main__':
    run()
""")
EOF

python3 /app/generate.py
rm /app/generate.py

useradd -m -s /bin/bash user || true
chmod -R 777 /app
chmod -R 777 /home/user
