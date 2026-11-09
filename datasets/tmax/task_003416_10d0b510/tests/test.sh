#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import math
import os
import secrets
import subprocess
import sys
import textwrap
import pytest

SO_PATH = "/home/user/libintegrate.so"
SCRIPT_PATH = "/home/user/test_math.py"
JSON_PATH = "/home/user/test_result.json"


def test_libintegrate_so_exists_and_is_elf():
    """Test that the compiled C shared library exists and is an ELF file."""
    assert os.path.isfile(SO_PATH), f"Shared library {SO_PATH} does not exist. Did you compile the Go code?"

    with open(SO_PATH, "rb") as f:
        magic = f.read(4)
    assert magic == b"\x7fELF", f"File {SO_PATH} is not a valid ELF binary."


def test_library_exports_working_calculate_pi():
    """Load the submitted library and exercise CalculatePi on verifier-chosen inputs."""
    steps = [1000 + secrets.randbelow(3000), 5000 + secrets.randbelow(5000)]
    helper = textwrap.dedent(r'''
        import ctypes
        import json
        import sys

        lib = ctypes.CDLL(sys.argv[1])
        fn = lib.CalculatePi
        fn.argtypes = [ctypes.c_int]
        fn.restype = ctypes.c_double
        values = [fn(int(value)) for value in sys.argv[2:]]
        print(json.dumps(values))
    ''')
    proc = subprocess.run(
        [sys.executable, "-c", helper, SO_PATH, *map(str, steps)],
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert proc.returncode == 0, f"Could not load/call CalculatePi:\n{proc.stderr}"
    try:
        actual = json.loads(proc.stdout)
    except json.JSONDecodeError:
        pytest.fail(f"CalculatePi helper produced invalid output: {proc.stdout!r}")

    assert len(actual) == len(steps)
    for n, value in zip(steps, actual):
        width = 1.0 / n
        expected = math.fsum(
            4.0 / (1.0 + ((i + 0.5) * width) ** 2)
            for i in range(n)
        ) * width
        assert math.isfinite(value), f"CalculatePi({n}) returned a non-finite value"
        assert abs(value - expected) < 2e-12, (
            f"CalculatePi({n}) returned {value}, expected {expected}"
        )


def test_python_script_uses_ctypes_and_executes():
    """Execute the submitted script while observing its ctypes configuration and call."""
    assert os.path.isfile(SCRIPT_PATH), f"Python script {SCRIPT_PATH} does not exist."
    if os.path.exists(JSON_PATH):
        os.unlink(JSON_PATH)

    harness = textwrap.dedent(r'''
        import ctypes
        import json
        import os
        import runpy
        import sys

        target = os.path.realpath(sys.argv[1])
        script = sys.argv[2]
        original_cdll = ctypes.CDLL
        calls = []
        loads = []

        class TrackedFunction:
            def __init__(self, function, name):
                object.__setattr__(self, "_function", function)
                object.__setattr__(self, "_name", name)

            @property
            def argtypes(self):
                return self._function.argtypes

            @argtypes.setter
            def argtypes(self, value):
                self._function.argtypes = value

            @property
            def restype(self):
                return self._function.restype

            @restype.setter
            def restype(self, value):
                self._function.restype = value

            def __getattr__(self, name):
                return getattr(self._function, name)

            def __setattr__(self, name, value):
                setattr(self._function, name, value)

            def __call__(self, *args, **kwargs):
                result = self._function(*args, **kwargs)
                if self._name == "CalculatePi":
                    calls.append((args, self._function.argtypes, self._function.restype, result))
                return result

        class TrackedLibrary:
            def __init__(self, name, *args, **kwargs):
                loads.append(os.path.realpath(os.fspath(name)))
                object.__setattr__(self, "_library", original_cdll(name, *args, **kwargs))

            def __getattr__(self, name):
                value = getattr(self._library, name)
                if name == "CalculatePi":
                    return TrackedFunction(value, name)
                return value

            def __setattr__(self, name, value):
                setattr(self._library, name, value)

        ctypes.CDLL = TrackedLibrary
        ctypes.cdll._dlltype = TrackedLibrary
        runpy.run_path(script, run_name="__main__")

        assert target in loads, f"Script did not load {target} using ctypes"
        matching = []
        for args, argtypes, restype, result in calls:
            if len(args) != 1:
                continue
            argument = getattr(args[0], "value", args[0])
            if argument == 1000000:
                matching.append((argtypes, restype, result))
        assert matching, "Script did not call CalculatePi with 1000000 steps"
        assert any(
            argtypes is not None
            and list(argtypes) == [ctypes.c_int]
            and restype is ctypes.c_double
            for argtypes, restype, _ in matching
        ), "Script did not configure CalculatePi argtypes=[ctypes.c_int] and restype=ctypes.c_double"

        assert os.path.isfile("/home/user/test_result.json"), "Script did not create test_result.json"
        with open("/home/user/test_result.json", "r") as f:
            data = json.load(f)
        assert any(data.get("result") == round(result, 6) for _, _, result in matching), \
            "JSON result was not the CalculatePi return value rounded to 6 places"
    ''')

    proc = subprocess.run(
        [sys.executable, "-c", harness, SO_PATH, SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        capture_output=True,
        timeout=60,
    )
    assert proc.returncode == 0, f"test_math.py failed verification:\n{proc.stdout}\n{proc.stderr}"


def test_result_json_exists_and_correct():
    """Test that test_result.json exists and contains the exact expected values."""
    assert os.path.isfile(JSON_PATH), f"JSON result file {JSON_PATH} does not exist. Did you run the Python script?"

    with open(JSON_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {JSON_PATH} is not valid JSON.")

    assert "module" in data, "Key 'module' missing from JSON."
    assert data["module"] == "libintegrate.so", f"Expected module 'libintegrate.so', got {data['module']}."

    assert "steps" in data, "Key 'steps' missing from JSON."
    assert data["steps"] == 1000000, f"Expected steps 1000000, got {data['steps']}."

    assert "result" in data, "Key 'result' missing from JSON."
    assert isinstance(data["result"], float), "Result should be a float."
    assert data["result"] == 3.141593, f"Expected result 3.141593, got {data['result']}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
