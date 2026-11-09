#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import shutil
import stat
import subprocess
import tempfile

TOKEN = "SUPPORT-TOKEN-9X8A-2B1C-4D5E"
TOKEN_PATH = "/home/user/token.txt"
SOURCE_PATH = "/home/user/regression.c"
REGRESSION_PATH = "/home/user/regression"
LEGACY_PATH = "/home/user/legacy_tool"
DUMP_PATH = "/home/user/mem.dump"


def run(path):
    return subprocess.run([path], capture_output=True, timeout=10)


def test_token_extraction():
    assert os.path.isfile(TOKEN_PATH), f"Expected {TOKEN_PATH} to exist."
    with open(TOKEN_PATH, "r") as f:
        content = f.read().strip()
    assert content == TOKEN, f"Expected token to be '{TOKEN}', but got '{content}'."


def test_regression_executable_exists():
    assert os.path.isfile(REGRESSION_PATH), f"Expected {REGRESSION_PATH} to exist."
    st = os.stat(REGRESSION_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Expected {REGRESSION_PATH} to be executable."
    with open(REGRESSION_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Expected regression to be a compiled native executable."


def test_regression_source_exists_and_compiles():
    assert os.path.isfile(SOURCE_PATH), f"Expected {SOURCE_PATH} to exist."
    compiled = tempfile.NamedTemporaryFile(prefix="regression-built-", delete=False)
    compiled.close()
    try:
        subprocess.run(
            ["gcc", SOURCE_PATH, "-o", compiled.name],
            check=True,
            capture_output=True,
            timeout=20,
        )
        with open(compiled.name, "rb") as f:
            assert f.read(4) == b"\x7fELF"
    finally:
        if os.path.exists(compiled.name):
            os.unlink(compiled.name)


def write_probe(marker, mode, code=0):
    program = f'''#!/usr/bin/python3
import json, os, signal, sys
with open({marker!r}, "w") as f:
    json.dump(sys.argv[1:], f)
if {mode!r} == "signal":
    os.kill(os.getpid(), signal.SIGSEGV)
sys.exit({code})
'''
    with open(LEGACY_PATH, "w") as f:
        f.write(program)
    os.chmod(LEGACY_PATH, 0o755)


def assert_probe_case(candidate, mode, code, expected):
    marker = tempfile.mktemp(prefix="legacy-invocation-")
    try:
        write_probe(marker, mode, code)
        result = run(candidate)
        assert result.returncode == expected, (
            f"For target mode={mode}, code={code}, expected regression status "
            f"{expected}, got {result.returncode}."
        )
        assert os.path.isfile(marker), "Regression did not execute /home/user/legacy_tool."
        with open(marker, "r") as f:
            args = json.load(f)
        assert len(args) == 1, f"Expected the tool to receive one argument, got {args!r}."
        value = args[0]
        assert value.startswith("TEST") and len(value) > 25, (
            "Regression did not supply an input guaranteed to trigger the documented bug."
        )
    finally:
        if os.path.exists(marker):
            os.unlink(marker)


def test_regression_behavior():
    # Preserve the original target while testing replacements.
    backup = tempfile.NamedTemporaryFile(prefix="legacy-tool-backup-", delete=False)
    backup.close()
    shutil.copy2(LEGACY_PATH, backup.name)

    built = tempfile.NamedTemporaryFile(prefix="regression-from-source-", delete=False)
    built.close()
    subprocess.run(["gcc", SOURCE_PATH, "-o", built.name], check=True, capture_output=True, timeout=20)

    try:
        # Original assertion: the regression succeeds when the real bug is present.
        if os.path.exists(DUMP_PATH):
            os.unlink(DUMP_PATH)
        result = run(REGRESSION_PATH)
        assert result.returncode == 0, (
            f"Expected regression test to return 0 when bug is present, got {result.returncode}."
        )
        assert os.path.isfile(DUMP_PATH), "Running the regression did not cause the tool to write mem.dump."
        with open(DUMP_PATH, "rb") as f:
            dump = f.read()
        assert TOKEN.encode() in dump, "The generated memory dump does not contain the support token."

        # Original assertion: it fails when a safe replacement exits zero.
        dummy_c_path = "/home/user/dummy_safe.c"
        with open(dummy_c_path, "w") as f:
            f.write("int main(void) { return 0; }\n")
        subprocess.run(["gcc", "-o", LEGACY_PATH, dummy_c_path], check=True, timeout=20)
        os.chmod(LEGACY_PATH, 0o755)
        result_safe = run(REGRESSION_PATH)
        assert result_safe.returncode == 1, (
            f"Expected regression test to return 1 when bug is NOT present (tool exits 0), "
            f"got {result_safe.returncode}."
        )
        os.unlink(dummy_c_path)

        # Exercise both the submitted binary and a fresh build from regression.c on
        # dynamically generated target implementations and verify actual invocation.
        non_crash = random.choice([n for n in range(2, 120) if n != 11])
        for candidate in (REGRESSION_PATH, built.name):
            assert_probe_case(candidate, "exit", 139, 0)
            assert_probe_case(candidate, "exit", non_crash, 1)
            assert_probe_case(candidate, "signal", 0, 0)
    finally:
        shutil.copy2(backup.name, LEGACY_PATH)
        os.chmod(LEGACY_PATH, 0o755)
        for path in (backup.name, built.name, "/home/user/dummy_safe.c"):
            if os.path.exists(path):
                os.unlink(path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
