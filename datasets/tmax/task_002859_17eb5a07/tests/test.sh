#!/bin/bash
set -e
mkdir -p /logs/verifier

BACKUP_DIR=$(mktemp -d)
cp -a /home/user/data "$BACKUP_DIR/data"
if [ -f /home/user/report.json ]; then
    cp -a /home/user/report.json "$BACKUP_DIR/report.json"
fi

restore_state() {
    rm -rf /home/user/data
    cp -a "$BACKUP_DIR/data" /home/user/data
    rm -f /home/user/report.json
    if [ -f "$BACKUP_DIR/report.json" ]; then
        cp -a "$BACKUP_DIR/report.json" /home/user/report.json
    fi
    rm -rf "$BACKUP_DIR"
}
trap restore_state EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import functools
import json
import math
import os
import re
import subprocess

PROJECT = "/home/user/project"
DATA = "/home/user/data"
REPORT = "/home/user/report.json"


def test_build_artifacts_exist():
    """Verify that the Makefile was fixed and artifacts were built."""
    lib_path = "/home/user/project/libeval.so"
    bin_path = "/home/user/project/eval_tool"

    assert os.path.isfile(lib_path), f"Shared library not found at {lib_path}. Did the Makefile build successfully?"
    assert os.path.isfile(bin_path), f"Go executable not found at {bin_path}. Did the Makefile build successfully?"


def test_report_json_content():
    """Verify the contents of the generated report.json file."""
    report_path = "/home/user/report.json"

    assert os.path.isfile(report_path), f"Result file not found at {report_path}."

    with open(report_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            raise AssertionError(f"File {report_path} does not contain valid JSON.")

    expected_data = {
        "ALPHA": 8,
        "BETA": 3,
        "DELTA": 25,
        "GAMMA": 100
    }

    assert data == expected_data, f"JSON content in {report_path} does not match the expected evaluated results."


def parse_semver(value):
    pattern = re.compile(
        r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
        r"(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?"
        r"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$"
    )
    match = pattern.fullmatch(value)
    assert match, f"Invalid verifier SemVer fixture: {value}"
    prerelease = None if match.group(4) is None else match.group(4).split(".")
    return (int(match.group(1)), int(match.group(2)), int(match.group(3)), prerelease)


def compare_semver(left, right):
    a = parse_semver(left)
    b = parse_semver(right)
    if a[:3] != b[:3]:
        return -1 if a[:3] < b[:3] else 1
    if a[3] is None or b[3] is None:
        if a[3] is None and b[3] is None:
            return 0
        return 1 if a[3] is None else -1
    for x, y in zip(a[3], b[3]):
        if x == y:
            continue
        x_numeric = x.isdigit()
        y_numeric = y.isdigit()
        if x_numeric and y_numeric:
            return -1 if int(x) < int(y) else 1
        if x_numeric != y_numeric:
            return -1 if x_numeric else 1
        return -1 if x < y else 1
    return (len(a[3]) > len(b[3])) - (len(a[3]) < len(b[3]))


def read_config(path):
    result = {}
    with open(path, encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if not line:
                continue
            key, values = line.split("=", 1)
            base, exponent = values.split(",", 1)
            result[key] = (float(base), float(exponent))
    return result


def test_clean_build_library_and_dynamic_pipeline():
    lib_path = os.path.join(PROJECT, "libeval.so")
    bin_path = os.path.join(PROJECT, "eval_tool")

    os.remove(lib_path)
    os.remove(bin_path)
    build = subprocess.run(
        ["make"], cwd=PROJECT, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=120
    )
    assert build.returncode == 0, "make failed:\n" + build.stdout
    assert os.path.isfile(lib_path)
    assert os.path.isfile(bin_path)
    assert os.access(bin_path, os.X_OK), "eval_tool is not executable"

    with open(lib_path, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", "libeval.so is not an ELF shared library"
    with open(bin_path, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", "eval_tool is not a compiled executable"

    library = ctypes.CDLL(lib_path)
    evaluate_power = library.evaluate_power
    evaluate_power.argtypes = [ctypes.c_double, ctypes.c_double]
    evaluate_power.restype = ctypes.c_double
    assert math.isclose(evaluate_power(2.5, 3.25), math.pow(2.5, 3.25), rel_tol=1e-12)

    dynamic_info = subprocess.run(
        ["readelf", "-d", bin_path], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=30
    )
    assert dynamic_info.returncode == 0, dynamic_info.stdout
    assert "libeval.so" in dynamic_info.stdout, "eval_tool is not dynamically linked to libeval.so"

    versions = [
        "1.2.0-alpha",
        "1.2.0",
        "1.8.4-rc.2",
        "1.8.4-rc.10",
        "1.7.9",
        "2.0.0",
        "2.3.1"
    ]
    with open(os.path.join(DATA, "versions.txt"), "w", encoding="utf-8") as handle:
        handle.write("\n".join(versions) + "\n")
    with open(os.path.join(DATA, "base.txt"), "w", encoding="utf-8") as handle:
        handle.write("ZETA=2.0,5.0\nMIDPOINT=3.0,4.0\nAARDVARK=81.0,0.5\n")

    eligible = [
        version for version in versions
        if compare_semver(version, "1.2.0") >= 0 and compare_semver(version, "2.0.0") < 0
    ]
    selected = max(eligible, key=functools.cmp_to_key(compare_semver))
    diff_path = os.path.join(DATA, "diff_" + selected + ".txt")
    with open(diff_path, "w", encoding="utf-8") as handle:
        handle.write("MIDPOINT=5.0,3.0\nONLYDIFF=4.0,-1.0\n")

    merged = read_config(os.path.join(DATA, "base.txt"))
    merged.update(read_config(diff_path))
    expected = {key: math.pow(*values) for key, values in merged.items()}

    if os.path.exists(REPORT):
        os.remove(REPORT)
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = PROJECT + (":" + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else "")
    run = subprocess.run(
        [bin_path], cwd=PROJECT, env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60
    )
    assert run.returncode == 0, "eval_tool failed:\n" + run.stdout
    assert os.path.isfile(REPORT), "eval_tool did not generate /home/user/report.json"

    with open(REPORT, encoding="utf-8") as handle:
        report_text = handle.read()
    actual = json.loads(report_text)
    assert actual == expected, f"Dynamic pipeline result was {actual!r}, expected {expected!r}"
    assert list(actual) == sorted(actual), "JSON keys are not alphabetically sorted"
    property_lines = [line for line in report_text.splitlines() if line.lstrip().startswith('"')]
    assert property_lines and all(line.startswith('  "') for line in property_lines), \
        "JSON was not emitted with a two-space indent"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
