#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import importlib
import importlib.machinery
import json
import math
import os
import subprocess
import tempfile
import uuid

import pytest

CLEAN_DIR = "/app/corpora/clean"
EVIL_DIR = "/app/corpora/evil"
SCRIPT_PATH = "/home/user/detect_instability.py"
MAKEFILE_PATH = "/app/libstatutils-1.2.0/Makefile"


def run_script(filepath, env=None):
    try:
        result = subprocess.run(
            ["python3", SCRIPT_PATH, filepath],
            capture_output=True,
            text=True,
            timeout=5,
            env=env,
        )
        return result.stdout.strip().split('\n')[-1].strip() if result.stdout else ""
    except subprocess.TimeoutExpired:
        return "TIMEOUT"
    except Exception as e:
        return f"ERROR: {str(e)}"


def run_script_strict(filepath, env=None):
    result = subprocess.run(
        ["python3", SCRIPT_PATH, filepath],
        capture_output=True,
        text=True,
        timeout=5,
        env=env,
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout in ("CLEAN", "CLEAN\n", "EVIL", "EVIL\n"), repr(result.stdout)
    return result.stdout.strip()


def installed_variance(samples):
    code = (
        "import json,sys,libstatutils; "
        "x=json.loads(sys.stdin.read()); "
        "v=libstatutils.variance(x); "
        "print(repr(v))"
    )
    result = subprocess.run(
        ["python3", "-I", "-c", code],
        input=json.dumps(samples),
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert result.returncode == 0, result.stderr
    return float(result.stdout.strip())


def write_csv(path, samples):
    with open(path, "w") as f:
        for value in samples:
            f.write(repr(value) + "\n")


def expected_label(samples):
    value = installed_variance(samples)
    fluctuates = any(x != samples[0] for x in samples[1:])
    if math.isnan(value) or value < 0.0 or (value == 0.0 and fluctuates):
        return "EVIL"
    if value > 0.0:
        return "CLEAN"
    return "EVIL"


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."


def test_clean_corpus():
    clean_files = glob.glob(os.path.join(CLEAN_DIR, "*.csv"))
    assert len(clean_files) > 0, f"No files found in {CLEAN_DIR}"

    failures = []
    for filepath in clean_files:
        output = run_script(filepath)
        if output != "CLEAN":
            failures.append((os.path.basename(filepath), output))

    if failures:
        msg = f"{len(failures)} of {len(clean_files)} clean modified (failed to output CLEAN). Offending files: "
        msg += ", ".join([f"{f} (output: {o})" for f, o in failures[:10]])
        pytest.fail(msg)


def test_evil_corpus():
    evil_files = glob.glob(os.path.join(EVIL_DIR, "*.csv"))
    assert len(evil_files) > 0, f"No files found in {EVIL_DIR}"

    failures = []
    for filepath in evil_files:
        output = run_script(filepath)
        if output != "EVIL":
            failures.append((os.path.basename(filepath), output))

    if failures:
        msg = f"{len(failures)} of {len(evil_files)} evil bypassed (failed to output EVIL). Offending files: "
        msg += ", ".join([f"{f} (output: {o})" for f, o in failures[:10]])
        pytest.fail(msg)


def test_makefile_fixed():
    if os.path.isfile(MAKEFILE_PATH):
        with open(MAKEFILE_PATH, "r") as f:
            content = f.read()
        assert "-ffast-math" not in content, "The Makefile still contains the unsafe '-ffast-math' flag."


def test_makefile_and_python_binding_installed():
    assert os.path.isfile(MAKEFILE_PATH), "The vendored Makefile was removed."
    with open(MAKEFILE_PATH) as f:
        content = f.read()
    assert "install_python" in content, "The install_python target is missing."

    code = r'''
import importlib.machinery
import importlib.metadata
import json
import libstatutils
origin = getattr(libstatutils, "__file__", "") or ""
print(json.dumps({
    "origin": origin,
    "is_extension": any(origin.endswith(s) for s in importlib.machinery.EXTENSION_SUFFIXES),
    "version": importlib.metadata.version("libstatutils"),
    "has_variance": callable(getattr(libstatutils, "variance", None)),
    "probe": libstatutils.variance([0.0, 1.0, 2.0])
}))
'''
    result = subprocess.run(
        ["python3", "-I", "-c", code],
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert result.returncode == 0, result.stderr
    info = json.loads(result.stdout)
    assert info["is_extension"], f"libstatutils is not an installed extension module: {info['origin']}"
    assert info["version"] == "1.2.0"
    assert info["has_variance"]
    assert info["probe"] > 0.0


def test_randomized_paths_are_classified_from_csv_and_installed_variance(tmp_path):
    cases = [
        [0.0, 1.0, 2.0, 4.0],
        [-3.5, 0.25, 7.75, 12.0, -1.0],
        [100000000.0, 100000001.0],
        [100000000.0, 100000000.01, 99999999.99, 100000000.02],
        [1.0e12, 1.0e12 + 0.001, 1.0e12 - 0.001, 1.0e12 + 0.002],
    ]
    random_dir = tmp_path / ("inputs_" + uuid.uuid4().hex)
    random_dir.mkdir()
    for index, samples in enumerate(cases):
        path = random_dir / (uuid.uuid4().hex + f"_{index}.csv")
        write_csv(path, samples)
        assert run_script_strict(str(path)) == expected_label(samples)


def test_script_calls_and_uses_libstatutils_variance(tmp_path):
    samples = [1.0, 2.0, 4.0]
    input_path = tmp_path / (uuid.uuid4().hex + ".csv")
    write_csv(input_path, samples)

    scenarios = [
        ("7.0", "CLEAN"),
        ("-1.0", "EVIL"),
        ("0.0", "EVIL"),
        ("float('nan')", "EVIL"),
    ]

    for return_expression, expected in scenarios:
        shim_dir = tmp_path / ("shim_" + uuid.uuid4().hex)
        shim_dir.mkdir()
        marker = shim_dir / "called.json"
        shim = shim_dir / "libstatutils.py"
        shim.write_text(
            "import json\n"
            "def variance(samples):\n"
            f"    open({str(marker)!r}, 'w').write(json.dumps(samples))\n"
            f"    return {return_expression}\n"
        )
        env = os.environ.copy()
        env["PYTHONPATH"] = str(shim_dir)
        output = run_script_strict(str(input_path), env=env)
        assert marker.is_file(), "detect_instability.py did not call libstatutils.variance"
        assert json.loads(marker.read_text()) == samples
        assert output == expected, (
            f"The script did not classify the value returned by libstatutils.variance; "
            f"expected {expected}, got {output}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
