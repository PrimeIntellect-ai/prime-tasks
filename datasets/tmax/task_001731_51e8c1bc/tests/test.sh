#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import shlex
import stat
import subprocess
import uuid
import pytest

LEGACY = "/home/user/legacy"
MAKEFILE = os.path.join(LEGACY, "Makefile")
VALIDATOR = os.path.join(LEGACY, "validator.py")
BINARY = os.path.join(LEGACY, "checksum_bin")
RESULT = "/home/user/result.txt"


def expected_checksum(text, alt):
    return (sum(text.encode("ascii")) + (42 if alt else 0)) % 256


def expected_validator_output(text):
    checksum = expected_checksum(text, True)
    return f"Result: {sum(range(checksum))}\n"


def remove_binary():
    if os.path.lexists(BINARY):
        os.remove(BINARY)


def run_make(*args):
    proc = subprocess.run(
        ["make", *args], cwd=LEGACY, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30
    )
    assert proc.returncode == 0, f"make {' '.join(args)} failed:\n{proc.stdout}"
    assert os.path.isfile(BINARY), "make did not create checksum_bin"
    assert os.access(BINARY, os.X_OK), "checksum_bin is not executable"
    return proc.stdout


def build_alt():
    remove_binary()
    output = run_make("ALT=1")
    assert "-DALT_POLY" in output, \
        f"make ALT=1 did not pass -DALT_POLY to the compiler:\n{output}"


def run_binary(text):
    proc = subprocess.run(
        [BINARY, text], cwd=LEGACY, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert proc.returncode == 0, f"checksum_bin failed for {text!r}: {proc.stderr}"
    assert proc.stdout.strip().isdigit(), f"Invalid checksum output: {proc.stdout!r}"
    return int(proc.stdout.strip())


def test_makefile_fixed():
    assert os.path.isfile(MAKEFILE), f"Makefile is missing at {MAKEFILE}"

    with open(MAKEFILE, "r") as f:
        lines = f.readlines()

    # Preserve the original syntax and conditional-build assertions.
    has_tab = any(line.startswith("\tgcc") for line in lines)
    assert has_tab, "Makefile must use a tab character for the compilation command recipe."

    content = "".join(lines)
    assert "ALT" in content and "-DALT_POLY" in content, \
        "Makefile must support conditional builds with ALT=1 passing -DALT_POLY to gcc."

    probes = ["MigrationTest2023", "abc", "Probe" + uuid.uuid4().hex]

    remove_binary()
    run_make()
    for text in probes:
        assert run_binary(text) == expected_checksum(text, False), \
            f"Default checksum logic is incorrect for {text!r}"

    build_alt()
    for text in probes:
        assert run_binary(text) == expected_checksum(text, True), \
            f"ALT checksum logic is incorrect for {text!r}"


def test_validator_python3_and_pipeline():
    assert os.path.isfile(VALIDATOR), f"Python script missing at {VALIDATOR}"

    with open(VALIDATOR, "r") as f:
        content = f.read()

    try:
        ast.parse(content)
    except SyntaxError as e:
        pytest.fail(f"{VALIDATOR} contains invalid Python 3 syntax: {e}")

    assert "xrange" not in content, "The script still uses Python 2 'xrange'."
    assert 'print "' not in content, "The script still uses Python 2 'print' statement syntax."

    build_alt()

    # Interpose a logging wrapper to verify validator.py actually invokes the
    # compiled checksum utility instead of hardcoding or reimplementing it.
    token = uuid.uuid4().hex
    real_binary = os.path.join(LEGACY, ".checksum_bin_real_" + token)
    call_log = "/tmp/checksum_calls_" + token
    os.rename(BINARY, real_binary)
    wrapper = (
        "#!/bin/sh\n"
        + "printf '%s\\n' \"$1\" >> " + shlex.quote(call_log) + "\n"
        + "exec " + shlex.quote(real_binary) + " \"$@\"\n"
    )
    with open(BINARY, "w") as f:
        f.write(wrapper)
    os.chmod(BINARY, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR |
                     stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH)

    inputs = ["MigrationTest2023", "DecodeProbe" + uuid.uuid4().hex]
    try:
        for text in inputs:
            proc = subprocess.run(
                ["python3", VALIDATOR, text], cwd=LEGACY, text=True,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
            )
            assert proc.returncode == 0, \
                f"validator.py failed for {text!r}: {proc.stderr}"
            assert proc.stdout == expected_validator_output(text), \
                f"Unexpected validator.py output for {text!r}: {proc.stdout!r}"

        assert os.path.isfile(call_log), "validator.py did not invoke checksum_bin"
        with open(call_log, "r") as f:
            calls = f.read().splitlines()
        assert calls == inputs, \
            f"validator.py did not pass the expected inputs to checksum_bin: {calls!r}"
    finally:
        if os.path.lexists(BINARY):
            os.remove(BINARY)
        os.rename(real_binary, BINARY)
        if os.path.exists(call_log):
            os.remove(call_log)


def test_result_txt():
    assert os.path.isfile(RESULT), f"Result file missing at {RESULT}"

    with open(RESULT, "r") as f:
        content = f.read().strip()
    assert content == "Result: 1711", \
        f"Expected 'Result: 1711', but found '{content}' in {RESULT}"

    build_alt()
    proc = subprocess.run(
        ["python3", VALIDATOR, "MigrationTest2023"], cwd=LEGACY,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert proc.returncode == 0, \
        f"validator.py failed for MigrationTest2023: {proc.stderr.decode(errors='replace')}"
    assert proc.stdout == expected_validator_output("MigrationTest2023").encode(), \
        f"Python script produced unexpected output: {proc.stdout!r}"

    with open(RESULT, "rb") as f:
        saved = f.read()
    assert saved == proc.stdout, \
        "result.txt must contain exactly the standard output of validator.py"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
