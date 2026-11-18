#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import json
import os
import shutil
import subprocess
import tempfile

import pytest

SCRIPT = "/home/user/py_telemetry/telemetry.py"
LIBRARY = "/home/user/py_telemetry/libmathops.so"
LOADAVG = "/home/user/mock_proc/loadavg"
MEMINFO = "/home/user/mock_proc/meminfo"
OUTPUT = "/home/user/telemetry_out.json"
WORKDIR = "/home/user/py_telemetry"


def get_expected_metrics():
    with open(LOADAVG, "r") as f:
        load_parts = f.read().split()
        load1 = float(load_parts[0])
        load5 = float(load_parts[1])
        load15 = float(load_parts[2])

    mem_total = 0
    mem_free = 0
    with open(MEMINFO, "r") as f:
        for line in f:
            if line.startswith("MemTotal:"):
                mem_total = int(line.split()[1])
            elif line.startswith("MemFree:"):
                mem_free = int(line.split()[1])

    return load1, load5, load15, mem_total, mem_free


def calculate_expected_score(load1, load5, load15, mem_total, mem_free):
    load_avg = (load1 + load5 + load15) / 3.0
    mem_ratio = float(mem_free) / float(mem_total)
    return (100.0 - (load_avg * 10.0)) * mem_ratio


def run_script():
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run(
        ["python3", SCRIPT],
        cwd=WORKDIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert os.path.isfile(OUTPUT), f"Output JSON file {OUTPUT} was not created by telemetry.py."
    with open(OUTPUT, "r") as f:
        return json.load(f)


def assert_output(data, metrics, score):
    load1, load5, load15, mem_total, mem_free = metrics
    assert set(data) == {"metrics", "score", "status"}
    assert set(data["metrics"]) == {
        "load1", "load5", "load15", "mem_total_kb", "mem_free_kb"
    }
    assert data["metrics"]["load1"] == pytest.approx(load1)
    assert data["metrics"]["load5"] == pytest.approx(load5)
    assert data["metrics"]["load15"] == pytest.approx(load15)
    assert data["metrics"]["mem_total_kb"] == mem_total
    assert data["metrics"]["mem_free_kb"] == mem_free
    rounded = round(score, 2)
    assert data["score"] == rounded
    assert data["status"] == ("CRITICAL" if score < 50.0 else "OK")


def write_inputs(load1, load5, load15, mem_total, mem_free):
    with open(LOADAVG, "w") as f:
        f.write(f"{load1} {load5} {load15} 4/321 9876\n")
    with open(MEMINFO, "w") as f:
        f.write(
            f"MemTotal:       {mem_total} kB\n"
            f"MemFree:        {mem_free} kB\n"
            "MemAvailable:    123456 kB\n"
            "Buffers:         6543 kB\n"
        )


def test_shared_library_exists():
    assert os.path.isfile(LIBRARY), f"Shared library {LIBRARY} was not created."


def test_python_script_exists():
    assert os.path.isfile(SCRIPT), f"Python script {SCRIPT} was not created."


def test_json_output_exists():
    assert os.path.isfile(OUTPUT), f"Output JSON file {OUTPUT} was not created."


def test_json_output_content():
    data = run_script()

    assert "metrics" in data, "Key 'metrics' missing from JSON output."
    assert "score" in data, "Key 'score' missing from JSON output."
    assert "status" in data, "Key 'status' missing from JSON output."

    metrics = data["metrics"]
    expected_keys = ["load1", "load5", "load15", "mem_total_kb", "mem_free_kb"]
    for k in expected_keys:
        assert k in metrics, f"Key '{k}' missing from metrics in JSON output."

    load1, load5, load15, mem_total, mem_free = get_expected_metrics()
    assert pytest.approx(metrics["load1"]) == load1, "load1 metric is incorrect."
    assert pytest.approx(metrics["load5"]) == load5, "load5 metric is incorrect."
    assert pytest.approx(metrics["load15"]) == load15, "load15 metric is incorrect."
    assert metrics["mem_total_kb"] == mem_total, "mem_total_kb metric is incorrect."
    assert metrics["mem_free_kb"] == mem_free, "mem_free_kb metric is incorrect."

    expected_score = calculate_expected_score(load1, load5, load15, mem_total, mem_free)
    expected_score_rounded = round(expected_score, 2)
    expected_status = "CRITICAL" if expected_score_rounded < 50.0 else "OK"
    assert data["score"] == expected_score_rounded, (
        f"Score is incorrect. Expected {expected_score_rounded}, got {data['score']}."
    )
    assert data["status"] == expected_status, (
        f"Status is incorrect. Expected {expected_status}, got {data['status']}."
    )


def test_ctypes_argtypes_and_restype_are_declared():
    with open(SCRIPT, "r") as f:
        tree = ast.parse(f.read(), filename=SCRIPT)

    imported = {}
    ctypes_imported = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for item in node.names:
                if item.name == "ctypes":
                    ctypes_imported = True
        elif isinstance(node, ast.ImportFrom) and node.module == "ctypes":
            ctypes_imported = True
            for item in node.names:
                imported[item.asname or item.name] = item.name
    assert ctypes_imported, "telemetry.py must import ctypes."

    def terminal_name(expr):
        if isinstance(expr, ast.Attribute):
            return expr.attr
        if isinstance(expr, ast.Name):
            return imported.get(expr.id, expr.id)
        return None

    declarations = {}
    loader_found = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and terminal_name(node.func) in {"CDLL", "LoadLibrary", "PyDLL"}:
            loader_found = True
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Attribute) and target.attr in {"argtypes", "restype"}:
                    key = ast.dump(target.value, include_attributes=False)
                    declarations.setdefault(key, {})[target.attr] = node.value

    assert loader_found, "telemetry.py must load the shared library through ctypes."
    valid = False
    for values in declarations.values():
        if "argtypes" not in values or "restype" not in values:
            continue
        args = values["argtypes"]
        if not isinstance(args, (ast.List, ast.Tuple)):
            continue
        arg_names = [terminal_name(item) for item in args.elts]
        restype_name = terminal_name(values["restype"])
        if arg_names == ["c_double", "c_double", "c_double", "c_long", "c_long"] and restype_name == "c_double":
            valid = True
            break
    assert valid, "calculate_score must define three c_double and two c_long argtypes and a c_double restype."


def test_shared_library_is_loadable_and_implements_calculation():
    try:
        library = ctypes.CDLL(LIBRARY)
        function = library.calculate_score
    except (OSError, AttributeError) as exc:
        pytest.fail(f"libmathops.so is not a loadable shared library exporting calculate_score: {exc}")

    function.argtypes = [ctypes.c_double, ctypes.c_double, ctypes.c_double, ctypes.c_long, ctypes.c_long]
    function.restype = ctypes.c_double
    for values in [
        (0.75, 1.25, 2.0, 9876543, 4567890),
        (6.2, 4.1, 3.3, 5000000001, 3000000007),
    ]:
        expected = calculate_expected_score(*values)
        assert function(*values) == pytest.approx(expected, rel=1e-12, abs=1e-12)


def test_script_parses_changed_inputs_and_uses_real_library():
    original_load = open(LOADAVG, "rb").read()
    original_mem = open(MEMINFO, "rb").read()
    try:
        for values in [
            (0.37, 1.91, 4.28, 7654321, 3456789),
            (7.4, 5.2, 2.6, 5000000001, 3000000007),
        ]:
            write_inputs(*values)
            data = run_script()
            assert_output(data, values, calculate_expected_score(*values))
    finally:
        with open(LOADAVG, "wb") as f:
            f.write(original_load)
        with open(MEMINFO, "wb") as f:
            f.write(original_mem)
        subprocess.run(["python3", SCRIPT], cwd=WORKDIR, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def test_script_calls_calculate_score_from_shared_library():
    original_load = open(LOADAVG, "rb").read()
    original_mem = open(MEMINFO, "rb").read()
    with tempfile.TemporaryDirectory() as tempdir:
        backup = os.path.join(tempdir, "submitted.so")
        probe_c = os.path.join(tempdir, "probe.c")
        probe_so = os.path.join(tempdir, "probe.so")
        shutil.copy2(LIBRARY, backup)
        with open(probe_c, "w") as f:
            f.write(r'''double calculate_score(double a, double b, double c, long mt, long mf) {
    return 13.0 + a * 1.25 - b * 0.75 + c * 2.5
           + (double)(mt % 997) * 0.01 + (double)(mf % 991) * 0.02;
}
''')
        subprocess.run(["gcc", "-shared", "-fPIC", probe_c, "-o", probe_so], check=True)
        values = (1.23, 4.56, 7.89, 5000000001, 3000000007)
        try:
            shutil.copy2(probe_so, LIBRARY)
            write_inputs(*values)
            data = run_script()
            expected = (
                13.0 + values[0] * 1.25 - values[1] * 0.75 + values[2] * 2.5
                + (values[3] % 997) * 0.01 + (values[4] % 991) * 0.02
            )
            assert_output(data, values, expected)
        finally:
            shutil.copy2(backup, LIBRARY)
            with open(LOADAVG, "wb") as f:
                f.write(original_load)
            with open(MEMINFO, "wb") as f:
                f.write(original_mem)
            subprocess.run(["python3", SCRIPT], cwd=WORKDIR, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
