#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import importlib.util
import json
import math
import os
import random
import subprocess
import sys
import threading
import time

import pytest

PIPELINE_DIR = "/home/user/legacy_pipeline"
VENV_PYTHON = "/home/user/venv/bin/python"
VENV_PIP = "/home/user/venv/bin/pip"
REPORT_PATH = "/home/user/debug_report.json"
SCRIPT_PATH = os.path.join(PIPELINE_DIR, "process_data.py")
SO_PATH = os.path.join(PIPELINE_DIR, "libfastcompute.so")


def test_venv_and_dependencies():
    assert os.path.exists(VENV_PYTHON), "Virtual environment python not found at /home/user/venv/bin/python"
    assert os.path.exists(VENV_PIP), "Virtual environment pip not found at /home/user/venv/bin/pip"

    out = subprocess.check_output([VENV_PIP, "list"], text=True)
    assert "requests" in out.lower(), "requests is not installed in the venv"
    assert "urllib3" in out.lower(), "urllib3 is not installed in the venv"

    try:
        subprocess.check_output([VENV_PIP, "check"], stderr=subprocess.STDOUT, text=True)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"pip check failed, indicating dependency conflicts: {e.output}")

    requirement_check = r'''
from importlib.metadata import version
from pip._vendor.packaging.requirements import Requirement

path = "/home/user/legacy_pipeline/requirements.txt"
requirements = []
with open(path, encoding="utf-8") as f:
    for raw in f:
        line = raw.strip()
        if line and not line.startswith("#"):
            requirements.append(Requirement(line))

by_name = {r.name.lower(): r for r in requirements}
assert "requests" in by_name, "requirements.txt does not require requests"
assert "urllib3" in by_name, "requirements.txt does not require urllib3"
for name in ("requests", "urllib3"):
    req = by_name[name]
    installed = version(name)
    assert installed in req.specifier, f"installed {name} {installed} does not satisfy repaired requirement {req}"
'''
    subprocess.run([VENV_PYTHON, "-c", requirement_check], check=True, text=True)


def test_makefile_and_compilation():
    makefile_path = os.path.join(PIPELINE_DIR, "Makefile")
    with open(makefile_path, encoding="utf-8") as f:
        content = f.read()
    assert "-lm" in content, "Makefile does not contain the required -lm linker flag"

    if os.path.lexists(SO_PATH):
        os.unlink(SO_PATH)
    result = subprocess.run(
        ["make", "-B"], cwd=PIPELINE_DIR, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT
    )
    assert result.returncode == 0, f"fresh compilation failed:\n{result.stdout}"
    assert os.path.isfile(SO_PATH), "libfastcompute.so was not produced by make"
    with open(SO_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "libfastcompute.so is not an ELF shared object"

    lib = ctypes.CDLL(SO_PATH)
    lib.compute_score.restype = ctypes.c_double
    lib.compute_score.argtypes = [ctypes.c_char_p]
    rng = random.Random(73491)
    for _ in range(12):
        payload = bytes(rng.randrange(32, 127) for _ in range(rng.randrange(1, 100)))
        expected = math.sqrt(sum(payload))
        actual = lib.compute_score(payload)
        assert math.isclose(actual, expected, rel_tol=0, abs_tol=1e-12), (
            f"compiled compute_score returned {actual}, expected {expected}"
        )


def test_debug_report():
    assert os.path.exists(REPORT_PATH), f"{REPORT_PATH} does not exist"
    with open(REPORT_PATH, encoding="utf-8") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("debug_report.json is not valid JSON")

    assert set(report) == {
        "missing_linker_flag", "crashing_string_length", "race_condition_variable"
    }, "debug_report.json does not have exactly the requested fields"
    assert report.get("missing_linker_flag") == "-lm", "missing_linker_flag is incorrect"
    assert report.get("crashing_string_length") == 128, "crashing_string_length is incorrect"
    assert report.get("race_condition_variable") == "total_score", "race_condition_variable is incorrect"


def load_process_module():
    old_cwd = os.getcwd()
    try:
        os.chdir(PIPELINE_DIR)
        name = f"process_data_under_test_{time.time_ns()}"
        spec = importlib.util.spec_from_file_location(name, SCRIPT_PATH)
        module = importlib.util.module_from_spec(spec)
        sys.modules[name] = module
        spec.loader.exec_module(module)
        return module
    finally:
        os.chdir(old_cwd)


def test_process_line_truncates_bytes_and_invokes_compute():
    module = load_process_module()
    calls = []

    class FakeLib:
        def compute_score(self, payload):
            assert isinstance(payload, bytes), "compute_score must receive encoded bytes"
            calls.append(payload)
            return math.sqrt(sum(payload))

    module.lib = FakeLib()
    module.total_score = 0.0
    lines = [
        "x" * 200,
        "é" * 90,
        "prefix-" + "€" * 60,
        "ordinary line",
    ]
    expected_total = 0.0
    for line in lines:
        expected_payload = line.encode("utf-8")[:127]
        expected_total += math.sqrt(sum(expected_payload))
        module.process_line(line)

    assert calls == [line.encode("utf-8")[:127] for line in lines], (
        "process_line did not pass each line, truncated to at most 127 bytes, to compute_score"
    )
    assert math.isclose(module.total_score, expected_total, rel_tol=0, abs_tol=1e-12), (
        "process_line did not aggregate the scores returned by the compute function"
    )


def test_process_line_aggregation_is_synchronized():
    module = load_process_module()

    class FakeLib:
        def compute_score(self, payload):
            return 1.0

    class RaceNumber:
        def __init__(self, value):
            self.value = value

        def __add__(self, other):
            old = self.value
            time.sleep(0.003)
            return RaceNumber(old + other)

    module.lib = FakeLib()
    module.total_score = RaceNumber(0.0)
    threads = [threading.Thread(target=module.process_line, args=(f"line-{i}",)) for i in range(60)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()

    assert isinstance(module.total_score, RaceNumber)
    assert module.total_score.value == 60.0, (
        f"concurrent aggregation lost updates: got {module.total_score.value}, expected 60"
    )


def test_process_data_execution():
    with open(SCRIPT_PATH, encoding="utf-8") as f:
        content = f.read()

    assert "Lock" in content or "Semaphore" in content or "RLock" in content or "mutex" in content.lower(), "process_data.py does not seem to use a lock for synchronization"
    assert "127" in content or "[:127]" in content, "process_data.py does not seem to truncate the string to 127 bytes to prevent buffer overflow"

    base_lines = [
        "short line",
        "another normal line",
        "A" * 50,
        "B" * 128,
        "C" * 20,
    ]
    expected = 100 * sum(math.sqrt(sum(line.encode("utf-8")[:127])) for line in base_lines)

    outputs = set()
    scores = []
    for _ in range(3):
        try:
            out = subprocess.check_output(
                [VENV_PYTHON, SCRIPT_PATH], stderr=subprocess.STDOUT,
                cwd=PIPELINE_DIR, text=True, timeout=30
            )
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
            pytest.fail(f"process_data.py crashed, timed out, or returned non-zero: {e}")

        score_lines = [line.strip() for line in out.splitlines() if "Final Score:" in line]
        assert len(score_lines) == 1, "process_data.py must output exactly one 'Final Score:' line"
        outputs.add(score_lines[0])
        try:
            scores.append(float(score_lines[0].split("Final Score:", 1)[1].strip()))
        except ValueError:
            pytest.fail(f"Final Score is not numeric: {score_lines[0]}")

    assert len(outputs) == 1, f"process_data.py output is not deterministic. Outputs seen: {outputs}"
    assert math.isfinite(scores[0]), "Final Score is not finite"
    assert math.isclose(scores[0], expected, rel_tol=0, abs_tol=1e-7), (
        f"Final Score is incorrect: got {scores[0]}, expected {expected}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
