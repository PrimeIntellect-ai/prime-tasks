#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import runpy
import subprocess

PROJECT_DIR = "/home/user/project"
PROCESSOR = os.path.join(PROJECT_DIR, "app", "processor.py")
LIBRARY = os.path.join(PROJECT_DIR, "lib", "libvalidator.so")
RESULTS = os.path.join(PROJECT_DIR, "data", "results.json")


def run_processor():
    return subprocess.run(
        ["python3", PROCESSOR],
        cwd="/tmp",
        text=True,
        capture_output=True,
        timeout=15,
        check=True,
    )


def test_directory_structure_and_files():
    """Verify that directories were created and files moved properly."""
    expected_structure = {
        "src": ["validator.c"],
        "include": ["validator.h"],
        "app": ["processor.py"],
        "data": ["limits.json", "requests.json", "results.json"],
        "lib": ["libvalidator.so"]
    }

    for dir_name, files in expected_structure.items():
        dir_path = os.path.join(PROJECT_DIR, dir_name)
        assert os.path.isdir(dir_path), f"Directory missing: {dir_path}"
        for filename in files:
            file_path = os.path.join(dir_path, filename)
            assert os.path.isfile(file_path), f"File missing: {file_path}"


def test_library_is_loadable_and_implements_validator():
    with open(LIBRARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "libvalidator.so is not an ELF shared library"

    lib = ctypes.CDLL(LIBRARY)
    fn = lib.check_rate_limit
    fn.argtypes = [ctypes.c_int, ctypes.c_int]
    fn.restype = ctypes.c_int

    cases = [
        (0, 0, 1), (1, 0, 0), (-1, 0, 1), (5, 5, 1),
        (6, 5, 0), (50, 100, 1), (101, 100, 0),
        (-2000000000, 2000000000, 1), (2000000000, -2000000000, 0),
    ]
    for tokens, maximum, expected in cases:
        assert fn(tokens, maximum) == expected


def test_results_json_content():
    """Execute the processor and verify its output."""
    if os.path.exists(RESULTS):
        os.remove(RESULTS)
    run_processor()
    assert os.path.isfile(RESULTS), f"Results file missing: {RESULTS}"

    with open(RESULTS, "r") as f:
        results = json.load(f)

    expected_results = [
        {"endpoint": "/api/login", "allowed": True},
        {"endpoint": "/api/login", "allowed": False},
        {"endpoint": "/api/data", "allowed": True},
        {"endpoint": "/api/admin", "allowed": False}
    ]

    assert results == expected_results, f"results.json content does not match expected output. Got: {results}"


def test_processor_ffi_bindings_and_data_driven_execution():
    limits_path = os.path.join(PROJECT_DIR, "data", "limits.json")
    requests_path = os.path.join(PROJECT_DIR, "data", "requests.json")
    paths = [limits_path, requests_path, RESULTS]
    saved = {path: open(path, "rb").read() if os.path.exists(path) else None for path in paths}

    limits = {"alpha": 0, "beta": 17, "gamma": -3}
    requests = [
        {"endpoint": "alpha", "tokens": 0},
        {"endpoint": "alpha", "tokens": 1},
        {"endpoint": "beta", "tokens": 17},
        {"endpoint": "beta", "tokens": 18},
        {"endpoint": "gamma", "tokens": -4},
        {"endpoint": "missing", "tokens": -1},
        {"endpoint": "missing", "tokens": 1},
    ]
    expected = [
        {"endpoint": req["endpoint"], "allowed": req["tokens"] <= limits.get(req["endpoint"], 0)}
        for req in requests
    ]

    try:
        with open(limits_path, "w") as f:
            json.dump(limits, f)
        with open(requests_path, "w") as f:
            json.dump(requests, f)
        if os.path.exists(RESULTS):
            os.remove(RESULTS)

        run_processor()
        with open(RESULTS, "r") as f:
            assert json.load(f) == expected

        namespace = runpy.run_path(PROCESSOR, run_name="__verifier_processor__")
        loaded_lib = namespace.get("lib")
        assert isinstance(loaded_lib, ctypes.CDLL), "processor.py did not load the library with ctypes.CDLL"
        fn = loaded_lib.check_rate_limit
        assert fn.argtypes == [ctypes.c_int, ctypes.c_int], "check_rate_limit argtypes are not two c_int values"
        assert fn.restype is ctypes.c_int, "check_rate_limit restype is not c_int"
        with open(RESULTS, "r") as f:
            assert json.load(f) == expected
    finally:
        for path, content in saved.items():
            if content is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                with open(path, "wb") as f:
                    f.write(content)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
