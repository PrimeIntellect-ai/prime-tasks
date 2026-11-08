#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import importlib.machinery
import json
import os
import re
import shutil
import stat
import subprocess
import sys

import pytest

APP = "/home/user/legacy_app"


@pytest.fixture(scope="session")
def built_extension():
    # Rebuild from the submitted setup.py and processor.c so a fabricated or stale
    # processor*.so cannot satisfy the verifier.
    shutil.rmtree(os.path.join(APP, "build"), ignore_errors=True)
    for path in glob.glob(os.path.join(APP, "processor*.so")):
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)

    proc = subprocess.run(
        [sys.executable, "setup.py", "build_ext", "--inplace"],
        cwd=APP,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
    )
    assert proc.returncode == 0, f"The extension could not be rebuilt:\n{proc.stdout}"

    so_files = glob.glob(os.path.join(APP, "processor*.so"))
    assert len(so_files) > 0, "The processor C-extension (.so file) was not found. Ensure setup.py compiles it successfully."

    candidates = [
        path for path in so_files
        if any(path.endswith(suffix) for suffix in importlib.machinery.EXTENSION_SUFFIXES)
    ]
    assert candidates, "No processor file has a valid Python extension-module suffix."
    extension = candidates[0]
    mode = os.stat(extension, follow_symlinks=False).st_mode
    assert stat.S_ISREG(mode), "The compiled processor extension must be a regular file."
    with open(extension, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The processor extension is not an ELF shared object."

    symbols = subprocess.run(
        ["nm", "-D", "--defined-only", extension],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=30,
    )
    assert symbols.returncode == 0, f"Could not inspect the compiled extension:\n{symbols.stdout}"
    assert re.search(r"\bprocess_payload_v2_fast\b", symbols.stdout), \
        "The rebuilt extension does not contain the correct symbol from libmagic.a."
    return extension


def test_mre_py_exists():
    mre_path = os.path.join(APP, "mre.py")
    assert os.path.isfile(mre_path), f"File {mre_path} does not exist. You must create the minimal reproducible example script."


def test_extension_compiled_and_runs(built_extension):
    # Import the freshly rebuilt shared object in a child process and exercise both
    # the anomalous payload and inputs whose answers are independently known.
    probe = r'''
import importlib.util
import json
import sys

path = sys.argv[1]
spec = importlib.util.spec_from_file_location("processor", path)
if spec is None or spec.loader is None:
    raise RuntimeError("could not create extension-module spec")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
values = {
    "anomaly": module.run(bytes.fromhex("cafebabe0042")),
    "empty": module.run(b""),
    "near_miss": module.run(bytes.fromhex("cafebabe0043")),
    "too_long": module.run(bytes.fromhex("cafebabe004200")),
}
print("PROBE_RESULT=" + json.dumps(values, sort_keys=True))
'''
    proc = subprocess.run(
        [sys.executable, "-c", probe, built_extension],
        cwd=APP,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert proc.returncode == 0, f"Importing or running the compiled extension failed:\n{proc.stdout}\n{proc.stderr}"
    marker = next((line for line in proc.stdout.splitlines() if line.startswith("PROBE_RESULT=")), None)
    assert marker is not None, f"The extension probe produced no result: {proc.stdout}"
    values = json.loads(marker.split("=", 1)[1])
    assert values["anomaly"] == "SUCCESS_DECODED_ANOMALY_99X"
    assert values["empty"] == "INVALID_PAYLOAD"
    assert values["near_miss"] == "INVALID_PAYLOAD"
    assert values["too_long"] == "INVALID_PAYLOAD"


def test_result_txt_exists_and_correct(built_extension):
    # Remove any prewritten answer and require the submitted MRE to recreate it.
    result_path = os.path.join(APP, "result.txt")
    if os.path.lexists(result_path):
        if os.path.isdir(result_path) and not os.path.islink(result_path):
            shutil.rmtree(result_path)
        else:
            os.unlink(result_path)

    proc = subprocess.run(
        [sys.executable, os.path.join(APP, "mre.py")],
        cwd=APP,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert proc.returncode == 0, f"mre.py failed when executed:\n{proc.stdout}\n{proc.stderr}"
    assert os.path.isfile(result_path), f"File {result_path} does not exist. The script mre.py was either not run or failed to create it."

    with open(result_path, "r") as f:
        content = f.read().strip()

    expected = "SUCCESS_DECODED_ANOMALY_99X"
    assert content == expected, f"Expected '{expected}' in result.txt, but got '{content}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
