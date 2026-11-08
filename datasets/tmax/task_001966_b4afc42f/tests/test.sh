#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import random
import secrets
import shutil
import struct
import subprocess
from collections import Counter

import pytest


def test_c_source_exists_and_contains_fast_mode():
    c_file = "/home/user/counter.c"
    assert os.path.exists(c_file), f"{c_file} does not exist."
    with open(c_file, "r", encoding="utf-8") as f:
        content = f.read()
    assert "FAST_MODE" in content, f"{c_file} does not contain 'FAST_MODE'."


def test_shared_library_exists():
    so_file = "/home/user/libcounter.so"
    assert os.path.exists(so_file), f"{so_file} does not exist."
    assert os.path.isfile(so_file), f"{so_file} is not a file."
    with open(so_file, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{so_file} is not an ELF shared library."


def test_python_script_exists_and_uses_ctypes():
    py_file = "/home/user/migrate.py"
    assert os.path.exists(py_file), f"{py_file} does not exist."
    with open(py_file, "r", encoding="utf-8") as f:
        content = f.read()
    assert "ctypes" in content, f"{py_file} does not import or use 'ctypes'."


def test_result_txt_contents():
    result_file = "/home/user/result.txt"
    assert os.path.exists(result_file), f"{result_file} does not exist."
    with open(result_file, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]
    expected = ["100", "200", "-5", "999", "42"]
    assert lines == expected, f"Contents of {result_file} do not match the expected top 5 integers. Expected {expected}, got {lines}."


def test_benchmark_json_contents():
    json_file = "/home/user/benchmark.json"
    assert os.path.exists(json_file), f"{json_file} does not exist."
    with open(json_file, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{json_file} does not contain valid JSON.")
    expected_data = {"status": "success", "language": "python3+C"}
    assert data == expected_data, f"Contents of {json_file} do not match expected JSON. Expected {expected_data}, got {data}."


def exercise_counter(path):
    lib = ctypes.CDLL(path)
    lib.init_counter.argtypes = []
    lib.init_counter.restype = None
    lib.add_values.argtypes = [ctypes.POINTER(ctypes.c_int), ctypes.c_int]
    lib.add_values.restype = None
    lib.get_count.argtypes = [ctypes.c_int]
    lib.get_count.restype = ctypes.c_int

    offset = secrets.randbelow(1000000) - 500000
    values = []
    expected = {}
    for i in range(3000):
        value = offset + i * 17
        count = 1 + (i % 5)
        expected[value] = count
        values.extend([value] * count)
    random.SystemRandom().shuffle(values)

    lib.init_counter()
    for start in range(0, len(values), 337):
        chunk = values[start:start + 337]
        array = (ctypes.c_int * len(chunk))(*chunk)
        lib.add_values(array, len(chunk))
    for value, count in expected.items():
        assert lib.get_count(value) == count, f"C counter returned the wrong count for {value}."
    absent = offset - 1234567
    assert absent not in expected
    assert lib.get_count(absent) == 0
    lib.init_counter()
    for value in list(expected)[:20]:
        assert lib.get_count(value) == 0, "init_counter() did not clear the counter."


def test_submitted_and_source_built_c_libraries_count_correctly():
    exercise_counter("/home/user/libcounter.so")
    rebuilt = "/tmp/rebuilt_counter.so"
    subprocess.run([
        "gcc", "-DFAST_MODE", "-fPIC", "-shared",
        "/home/user/counter.c", "-o", rebuilt
    ], check=True, timeout=30, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    exercise_counter(rebuilt)


def read_results():
    with open("/home/user/result.txt", "r", encoding="utf-8") as f:
        return [int(line.strip()) for line in f if line.strip()]


def check_benchmark():
    with open("/home/user/benchmark.json", "r", encoding="utf-8") as f:
        assert json.load(f) == {"status": "success", "language": "python3+C"}


def run_migrate():
    subprocess.run(
        ["python3", "/home/user/migrate.py"],
        cwd="/home/user", check=True, timeout=30,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )


def test_migrate_executes_and_calls_the_c_api_on_derived_input():
    paths = ["/home/user/data.bin", "/home/user/libcounter.so",
             "/home/user/result.txt", "/home/user/benchmark.json"]
    backups = {}
    for path in paths:
        if os.path.exists(path):
            backup = "/tmp/backup_" + os.path.basename(path)
            shutil.copy2(path, backup)
            backups[path] = backup

    token = secrets.randbelow(100000000)
    distinct = set()
    while len(distinct) < 60:
        distinct.add(secrets.randbelow(2000000001) - 1000000000)
    keys = list(distinct)
    values = []
    for i, value in enumerate(keys):
        frequency = 3 + ((i * 11 + token) % 37)
        values.extend([value] * frequency)
    # Force a frequency tie among two otherwise dominant values so tie-breaking is tested.
    values.extend([keys[0]] * 100)
    values.extend([keys[1]] * (100 + (Counter(values)[keys[0]] - Counter(values)[keys[1]])))
    random.SystemRandom().shuffle(values)
    counts = Counter(values)
    expected = [v for v, _ in sorted(counts.items(), key=lambda item: (item[1], item[0]), reverse=True)[:5]]

    wrapper_source = r'''
#include <stdio.h>
#include <stdlib.h>
#define CAP 16384
static int keys[CAP];
static int counts[CAP];
static unsigned char used[CAP];
static FILE *logfile(void) { return fopen("/tmp/counter_calls.log", "a"); }
static unsigned hash_int(int v) { unsigned x=(unsigned)v; x ^= x>>16; x*=0x7feb352dU; x^=x>>15; return x; }
static int slot(int v) { unsigned p=hash_int(v)%CAP; while(used[p] && keys[p]!=v) p=(p+1)%CAP; return (int)p; }
void init_counter(void) { for(int i=0;i<CAP;i++){used[i]=0;counts[i]=0;} FILE *f=logfile(); if(f){fprintf(f,"I\n");fclose(f);} }
void add_values(const int *data, int count) { for(int i=0;i<count;i++){int p=slot(data[i]);if(!used[p]){used[p]=1;keys[p]=data[i];}counts[p]++;} FILE *f=logfile(); if(f){fprintf(f,"A %d\n",count);fclose(f);} }
int get_count(int value) { int p=slot(value); int r=used[p]?counts[p]:0; FILE *f=logfile(); if(f){fprintf(f,"G %d\n",value);fclose(f);} return r; }
'''

    try:
        with open("/home/user/data.bin", "wb") as f:
            f.write(struct.pack("<" + "i" * len(values), *values))
        for output in ("/home/user/result.txt", "/home/user/benchmark.json"):
            if os.path.exists(output):
                os.remove(output)

        # Execute the submitted script against the submitted shared library.
        run_migrate()
        assert read_results() == expected
        check_benchmark()

        # Replace the library temporarily with an instrumented, functional C API to
        # establish that migrate.py actually initializes, feeds, and queries C.
        with open("/tmp/instrumented_counter.c", "w", encoding="utf-8") as f:
            f.write(wrapper_source)
        subprocess.run([
            "gcc", "-fPIC", "-shared", "/tmp/instrumented_counter.c",
            "-o", "/home/user/libcounter.so"
        ], check=True, timeout=30, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if os.path.exists("/tmp/counter_calls.log"):
            os.remove("/tmp/counter_calls.log")
        for output in ("/home/user/result.txt", "/home/user/benchmark.json"):
            if os.path.exists(output):
                os.remove(output)
        run_migrate()
        assert read_results() == expected
        check_benchmark()

        with open("/tmp/counter_calls.log", "r", encoding="utf-8") as f:
            calls = [line.strip().split() for line in f if line.strip()]
        assert any(call[0] == "I" for call in calls), "migrate.py did not call init_counter()."
        assert sum(int(call[1]) for call in calls if call[0] == "A") == len(values), \
            "migrate.py did not pass all input integers to add_values()."
        queried = {int(call[1]) for call in calls if call[0] == "G"}
        assert set(counts).issubset(queried), \
            "migrate.py did not obtain the frequencies of the input values from get_count()."
    finally:
        for path in paths:
            if path in backups:
                shutil.copy2(backups[path], path)
            elif os.path.exists(path):
                os.remove(path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
