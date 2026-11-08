#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import math
import os
import re
import secrets
import subprocess
import textwrap

import pytest

PROJECT_DIR = "/home/user/project"
LIB_PATH = os.path.join(PROJECT_DIR, "libmathcodec.so")
PY_PATH = os.path.join(PROJECT_DIR, "test_codec.py")
PROCESSOR_PATH = os.path.join(PROJECT_DIR, "processor")


def run_checked(cmd, **kwargs):
    result = subprocess.run(cmd, text=True, capture_output=True, **kwargs)
    assert result.returncode == 0, (
        f"Command failed ({result.returncode}): {cmd}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def expected_line(text, decimals=2):
    return " ".join(
        f"{math.sqrt(ord(char)) + math.log2(i + 1):.{decimals}f}"
        for i, char in enumerate(text)
    )


@pytest.fixture(scope="session", autouse=True)
def exercise_pipeline():
    assert os.path.isfile(os.path.join(PROJECT_DIR, "Makefile"))
    assert os.path.isfile(os.path.join(PROJECT_DIR, "mathcodec.c"))
    assert os.path.isfile(PY_PATH), f"Python script {PY_PATH} does not exist."

    if os.path.lexists(LIB_PATH):
        os.remove(LIB_PATH)
    run_checked(["make", "-B"], cwd=PROJECT_DIR)
    assert os.path.isfile(LIB_PATH), f"Shared library {LIB_PATH} was not built."

    dynamic = run_checked(["readelf", "-d", LIB_PATH]).stdout
    assert re.search(r"\(NEEDED\).*libm\.so", dynamic), (
        "libmathcodec.so is not linked against the math library (-lm)."
    )

    # Independently exercise the freshly rebuilt C library on verifier-selected data.
    library = ctypes.CDLL(LIB_PATH)
    library.encode.argtypes = [
        ctypes.c_char_p,
        ctypes.POINTER(ctypes.c_double),
        ctypes.c_int,
    ]
    library.encode.restype = None
    sample = ("Q" + secrets.choice("ABCDEFGH") + "7Z").encode("ascii")
    result = (ctypes.c_double * len(sample))()
    library.encode(sample, result, len(sample))
    for i, byte in enumerate(sample):
        expected = math.sqrt(byte) + math.log2(i + 1)
        assert math.isclose(result[i], expected, rel_tol=1e-12, abs_tol=1e-12)

    # Run the submitted fixture while wrapping ctypes.CDLL, proving that it loads
    # the requested library and actually calls encode with exactly b"TEST".
    probe_path = "/tmp/fixture_probe.json"
    launcher_path = "/tmp/run_fixture_probe.py"
    launcher = textwrap.dedent(f'''\
        import ctypes
        import json
        import os
        import runpy

        TARGET = {LIB_PATH!r}
        PROBE = {probe_path!r}
        SCRIPT = {PY_PATH!r}
        real_cdll = ctypes.CDLL
        events = {{"loads": [], "calls": []}}

        class EncodeProxy:
            def __init__(self, function):
                object.__setattr__(self, "_function", function)

            def __getattr__(self, name):
                return getattr(self._function, name)

            def __setattr__(self, name, value):
                setattr(self._function, name, value)

            def __call__(self, *args):
                if len(args) >= 3:
                    raw_len = getattr(args[2], "value", args[2])
                    length = int(raw_len)
                    if isinstance(args[0], (bytes, bytearray)):
                        data = bytes(args[0][:length])
                    else:
                        data = ctypes.string_at(args[0], length)
                    events["calls"].append({{"data": list(data), "len": length}})
                return self._function(*args)

        class LibraryProxy:
            def __init__(self, library):
                object.__setattr__(self, "_library", library)

            def __getattr__(self, name):
                value = getattr(self._library, name)
                return EncodeProxy(value) if name == "encode" else value

        def tracked_cdll(name, *args, **kwargs):
            path = os.fsdecode(os.fspath(name))
            events["loads"].append(path)
            loaded = real_cdll(name, *args, **kwargs)
            if os.path.abspath(path) == TARGET:
                return LibraryProxy(loaded)
            return loaded

        ctypes.CDLL = tracked_cdll
        ctypes.cdll.LoadLibrary = tracked_cdll
        try:
            runpy.run_path(SCRIPT, run_name="__main__")
        finally:
            with open(PROBE, "w", encoding="utf-8") as probe:
                json.dump(events, probe)
    ''')
    with open(launcher_path, "w", encoding="utf-8") as launcher_file:
        launcher_file.write(launcher)
    if os.path.exists(probe_path):
        os.remove(probe_path)
    if os.path.exists(os.path.join(PROJECT_DIR, "python_test_out.txt")):
        os.remove(os.path.join(PROJECT_DIR, "python_test_out.txt"))
    run_checked(["python3", launcher_path], cwd=PROJECT_DIR)
    with open(probe_path, "r", encoding="utf-8") as probe_file:
        probe = json.load(probe_file)
    assert LIB_PATH in probe["loads"], (
        "test_codec.py did not load /home/user/project/libmathcodec.so with ctypes."
    )
    assert any(call == {"data": [84, 69, 83, 84], "len": 4} for call in probe["calls"]), (
        'test_codec.py did not call encode with the exact byte string b"TEST" and length 4.'
    )

    if os.path.lexists(PROCESSOR_PATH):
        os.remove(PROCESSOR_PATH)
    run_checked(["go", "build", "-o", "processor", "processor.go"], cwd=PROJECT_DIR)
    assert os.path.isfile(PROCESSOR_PATH), f"Go binary {PROCESSOR_PATH} was not built."
    assert os.access(PROCESSOR_PATH, os.X_OK), f"Go binary {PROCESSOR_PATH} is not executable."

    environment = os.environ.copy()
    environment["LD_LIBRARY_PATH"] = PROJECT_DIR
    original_output = os.path.join(PROJECT_DIR, "output.txt")
    if os.path.exists(original_output):
        os.remove(original_output)
    run_checked(
        [PROCESSOR_PATH, os.path.join(PROJECT_DIR, "input.txt"), original_output],
        cwd=PROJECT_DIR,
        env=environment,
    )

    # Also exercise the processor on verifier-selected input to reject fixed output.
    challenge_lines = [
        "R" + secrets.token_hex(3).upper(),
        "PIPE" + secrets.choice("ABCDEFGH"),
        secrets.choice("JKLMNPQR") + "42",
    ]
    challenge_input = "/tmp/processor_challenge_input.txt"
    challenge_output = "/tmp/processor_challenge_output.txt"
    with open(challenge_input, "w", encoding="ascii") as challenge_file:
        challenge_file.write("\n".join(challenge_lines) + "\n")
    if os.path.exists(challenge_output):
        os.remove(challenge_output)
    run_checked(
        [PROCESSOR_PATH, challenge_input, challenge_output],
        cwd=PROJECT_DIR,
        env=environment,
    )
    with open(challenge_output, "r", encoding="utf-8") as challenge_file:
        actual = [line.strip() for line in challenge_file.read().splitlines()]
    expected = [expected_line(line) for line in challenge_lines]
    assert actual == expected, f"Processor challenge output mismatch: expected {expected}, got {actual}"


def test_makefile_fixed_and_lib_built():
    assert os.path.isfile(LIB_PATH), f"Shared library {LIB_PATH} was not built."


def test_python_script_exists():
    assert os.path.isfile(PY_PATH), f"Python script {PY_PATH} does not exist."


def test_python_test_out():
    out_path = os.path.join(PROJECT_DIR, "python_test_out.txt")
    assert os.path.isfile(out_path), f"Output file {out_path} does not exist."
    with open(out_path, "r", encoding="utf-8") as output_file:
        content = output_file.read().strip()

    expected_vals = []
    for i, char in enumerate("TEST"):
        val = math.sqrt(ord(char)) + math.log2(i + 1)
        expected_vals.append(f"{val:.3f}")
    expected_str = ", ".join(expected_vals)
    assert content.replace(" ", "") == expected_str.replace(" ", ""), (
        f"python_test_out.txt content mismatch. Expected something like {expected_str}, got {content}"
    )


def test_go_processor_built():
    assert os.path.isfile(PROCESSOR_PATH), f"Go binary {PROCESSOR_PATH} was not built."
    assert os.access(PROCESSOR_PATH, os.X_OK), f"Go binary {PROCESSOR_PATH} is not executable."


def test_go_processor_output():
    out_path = os.path.join(PROJECT_DIR, "output.txt")
    assert os.path.isfile(out_path), f"Output file {out_path} does not exist."
    with open(out_path, "r", encoding="utf-8") as output_file:
        lines = [line.strip() for line in output_file.read().strip().split("\n")]

    assert len(lines) == 4, f"Expected 4 lines in output.txt, got {len(lines)}"
    expected_lines = [expected_line(text) for text in ["HELLO", "WORLD", "MATH", "CODE"]]
    assert lines[0] == expected_lines[0], (
        f"First line of output.txt mismatch. Expected '{expected_lines[0]}', got '{lines[0]}'"
    )
    assert lines == expected_lines, f"output.txt mismatch. Expected {expected_lines}, got {lines}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
