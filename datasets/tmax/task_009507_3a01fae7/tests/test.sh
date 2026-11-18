#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import re
import string
import subprocess
import tempfile

INPUT = "/home/user/encrypted.dat"
OUTPUT = "/home/user/redacted.txt"
SOURCE = "/home/user/secure_processor.c"
PROGRAM = "/home/user/secure_processor"
HEADER = b"Content-Security-Policy: default-src 'none';\n\n"
ORIGINAL_PLAINTEXT = (
    b"Patient records show John Doe has SSN 123-45-6789 and Jane Doe has SSN "
    b"987-65-4321. Do not share."
)
ORIGINAL_EXPECTED = HEADER + (
    b"Patient records show John Doe has SSN ***-**-**** and Jane Doe has SSN "
    b"***-**-****. Do not share."
)


def test_redacted_txt_exists_and_correct():
    assert os.path.exists(OUTPUT), f"Missing {OUTPUT}"
    assert os.path.isfile(OUTPUT), f"{OUTPUT} is not a file"
    with open(OUTPUT, "rb") as f:
        actual_content = f.read()
    assert actual_content == ORIGINAL_EXPECTED, f"The contents of {OUTPUT} do not match the expected output."


def test_secure_processor_c_exists_and_uses_seccomp():
    assert os.path.exists(SOURCE), f"Missing {SOURCE}"
    assert os.path.isfile(SOURCE), f"{SOURCE} is not a file"
    with open(SOURCE, "r", encoding="utf-8") as f:
        content = f.read()
    has_prctl = re.search(r"prctl\s*\(", content)
    has_seccomp = re.search(r"SECCOMP_MODE_STRICT", content) or re.search(r"1", content)
    assert has_prctl, f"{SOURCE} does not seem to call prctl()"
    assert "prctl" in content, "prctl call not found in source code."


def test_secure_processor_executable_exists():
    assert os.path.exists(PROGRAM), f"Missing {PROGRAM}"
    assert os.path.isfile(PROGRAM), f"{PROGRAM} is not a file"
    assert os.access(PROGRAM, os.X_OK), f"{PROGRAM} is not executable"
    with open(PROGRAM, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{PROGRAM} is not a compiled ELF executable"


def redact_ssns(data):
    return re.sub(rb"(?<!\d)\d{3}-\d{2}-\d{4}(?!\d)", b"***-**-****", data)


def syscall_name(line):
    match = re.match(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\(", line)
    return match.group(1) if match else None


def successful_open_of(line, basename):
    if syscall_name(line) not in {"open", "openat"}:
        return False
    if not re.search(r"=\s*[0-9]+\s*$", line):
        return False
    quoted = re.findall(r'"([^"\\]*(?:\\.[^"\\]*)*)"', line)
    return any(os.path.basename(value) == basename for value in quoted)


def assert_strict_seccomp_trace(prefix):
    trace_paths = sorted(glob.glob(prefix + "*"))
    assert trace_paths, "strace did not produce a trace"

    processing_trace = None
    for path in trace_paths:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            lines = f.read().splitlines()
        if (any(successful_open_of(line, "encrypted.dat") for line in lines) and
                any(successful_open_of(line, "redacted.txt") for line in lines)):
            assert processing_trace is None, "input/output processing was split across multiple processes"
            processing_trace = lines

    assert processing_trace is not None, "program did not open both required files"
    lines = processing_trace
    calls = [(i, syscall_name(line), line) for i, line in enumerate(lines) if syscall_name(line)]

    input_call = next((entry for entry in calls if successful_open_of(entry[2], "encrypted.dat")), None)
    output_call = next((entry for entry in calls if successful_open_of(entry[2], "redacted.txt")), None)
    assert input_call is not None and output_call is not None

    strict_call = next(
        (entry for entry in calls
         if entry[1] == "prctl"
         and "PR_SET_SECCOMP" in entry[2]
         and "SECCOMP_MODE_STRICT" in entry[2]
         and re.search(r"=\s*0\s*$", entry[2])),
        None,
    )
    assert strict_call is not None, "strict seccomp was not successfully enabled"

    first_open_index = min(input_call[0], output_call[0])
    strict_index = strict_call[0]
    between = [entry for entry in calls if first_open_index <= entry[0] <= strict_index]
    assert len(between) == 3, "seccomp must be enabled immediately after opening input and output"
    assert successful_open_of(between[0][2], "encrypted.dat") or successful_open_of(between[0][2], "redacted.txt")
    assert successful_open_of(between[1][2], "encrypted.dat") or successful_open_of(between[1][2], "redacted.txt")
    assert {os.path.basename(re.findall(r'"([^"\\]*(?:\\.[^"\\]*)*)"', between[0][2])[-1]),
            os.path.basename(re.findall(r'"([^"\\]*(?:\\.[^"\\]*)*)"', between[1][2])[-1])} == {
                "encrypted.dat", "redacted.txt"
            }
    assert between[2][1] == "prctl"

    allowed_after = {"read", "write", "exit", "sigreturn", "rt_sigreturn"}
    forbidden = [entry[2] for entry in calls if entry[0] > strict_index and entry[1] not in allowed_after]
    assert not forbidden, "forbidden syscall(s) after strict seccomp: " + "; ".join(forbidden)


def run_and_check(program, plaintext, key):
    encrypted = bytes(byte ^ key for byte in plaintext)
    with open(INPUT, "wb") as f:
        f.write(encrypted)
    try:
        os.unlink(OUTPUT)
    except FileNotFoundError:
        pass

    prefix = tempfile.mktemp(prefix="secure_processor_trace_")
    try:
        result = subprocess.run(
            ["strace", "-ff", "-qq", "-o", prefix, "--", program],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        assert result.returncode == 0, (
            f"{program} failed with status {result.returncode}: "
            + result.stderr.decode("utf-8", "replace")
        )
        assert os.path.isfile(OUTPUT), f"{program} did not create {OUTPUT}"
        with open(OUTPUT, "rb") as f:
            actual = f.read()
        expected = HEADER + redact_ssns(plaintext)
        assert actual == expected, f"{program} produced incorrect output for a verifier-generated input"
        assert_strict_seccomp_trace(prefix)
    finally:
        for path in glob.glob(prefix + "*"):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass


def test_program_and_source_implement_processing_and_sandboxing():
    with open(INPUT, "rb") as f:
        original_encrypted = f.read()
    with open(OUTPUT, "rb") as f:
        original_output = f.read()

    assert original_encrypted, "encrypted input is empty"
    key = original_encrypted[0] ^ ORIGINAL_PLAINTEXT[0]
    assert bytes(byte ^ key for byte in original_encrypted) == ORIGINAL_PLAINTEXT, "could not derive the backend XOR key"

    rebuilt = "/tmp/verifier_secure_processor"
    compile_result = subprocess.run(
        ["gcc", "-O2", "-o", rebuilt, SOURCE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert compile_result.returncode == 0, (
        "secure_processor.c does not compile: "
        + compile_result.stderr.decode("utf-8", "replace")
    )

    rng = random.SystemRandom()
    token = "".join(rng.choice(string.ascii_letters + string.digits) for _ in range(40)).encode()
    ssn1 = f"{rng.randrange(100,1000):03d}-{rng.randrange(10,100):02d}-{rng.randrange(1000,10000):04d}".encode()
    ssn2 = f"{rng.randrange(100,1000):03d}-{rng.randrange(10,100):02d}-{rng.randrange(1000,10000):04d}".encode()
    generated = b"Verifier " + token + b" reports SSN " + ssn1 + b"; marker Z; second SSN " + ssn2 + b"."
    long_generated = b"A" * 8190 + b" SSN " + ssn1 + b" tail " + token

    try:
        run_and_check(PROGRAM, ORIGINAL_PLAINTEXT, key)
        run_and_check(PROGRAM, generated, key)
        run_and_check(rebuilt, long_generated, key)
    finally:
        with open(INPUT, "wb") as f:
            f.write(original_encrypted)
        with open(OUTPUT, "wb") as f:
            f.write(original_output)
        try:
            os.unlink(rebuilt)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
