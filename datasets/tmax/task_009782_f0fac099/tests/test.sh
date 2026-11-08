#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import signal
import string
import subprocess
import tempfile

REPO = "/home/user/profiler_app"
SOURCE = os.path.join(REPO, "decoder.c")
SOLUTION = "/home/user/solution.txt"
WAL = "/home/user/data/metrics.db-wal"
EXPECTED_CONTENT = "SYSTEM_RECOVERY_SUCCESS_9912"


def git(*args):
    return subprocess.check_output(["git", "-C", REPO, *args], stderr=subprocess.STDOUT)


def recover_key_from_history():
    commits = git("rev-list", "--reverse", "HEAD").decode().splitlines()
    assert commits, "Git repository has no commits"

    previous_key = None
    removed_key = None
    for commit in commits:
        source = git("show", f"{commit}:decoder.c")
        match = re.search(rb'HARDCODED_KEY\s*=\s*"([^"]+)"', source)
        current_key = match.group(1).decode() if match else None
        if previous_key is not None and current_key is None:
            removed_key = previous_key
        previous_key = current_key

    assert removed_key, "Could not find a commit that removed the hardcoded XOR key"
    return removed_key


def recover_payload_from_wal():
    assert os.path.isfile(WAL), f"Intact WAL file is missing: {WAL}"
    with open(WAL, "rb") as f:
        wal = f.read()
    matches = re.findall(rb"critical_crash([0-9a-fA-F]{56})", wal)
    assert matches, "Could not recover the critical_crash payload from the WAL"
    assert len(set(matches)) == 1, "WAL contains ambiguous critical_crash payloads"
    return matches[0].decode()


def xor_plaintext(hex_payload, key):
    data = bytes.fromhex(hex_payload)
    key_bytes = key.encode()
    return bytes(value ^ key_bytes[i % len(key_bytes)] for i, value in enumerate(data))


def run_decoder(path, hex_payload, key):
    proc = subprocess.Popen(
        [path, hex_payload, key],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        start_new_session=True,
    )
    try:
        stdout, stderr = proc.communicate(timeout=3)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        proc.communicate()
        raise AssertionError(f"Decoder {path} hung while processing a valid payload")
    assert proc.returncode == 0, (
        f"Decoder {path} exited with {proc.returncode}: "
        f"{stderr.decode(errors='replace')}"
    )
    return stdout.rstrip(b"\r\n")


def decoder_cases(task_payload, task_key):
    cases = [(task_payload, task_key, xor_plaintext(task_payload, task_key))]
    alphabet = string.ascii_letters + string.digits + "_-"
    for length in (1, 2, 3, 7, 19, 31, 64):
        plaintext = "".join(secrets.choice(alphabet) for _ in range(length)).encode()
        key = "".join(secrets.choice(string.ascii_letters + string.digits) for _ in range(11))
        encrypted = bytes(
            value ^ ord(key[i % len(key)]) for i, value in enumerate(plaintext)
        ).hex()
        cases.append((encrypted, key, plaintext))
    return cases


def assert_decoder_works(path, cases):
    for payload, key, expected in cases:
        actual = run_decoder(path, payload, key)
        assert actual == expected, (
            f"Decoder {path} produced {actual!r}, expected {expected!r}"
        )


def submitted_executables():
    found = []
    for root, dirs, files in os.walk(REPO):
        if ".git" in dirs:
            dirs.remove(".git")
        for name in files:
            path = os.path.join(root, name)
            if not os.path.isfile(path) or not os.access(path, os.X_OK):
                continue
            try:
                with open(path, "rb") as f:
                    if f.read(4) == b"\x7fELF":
                        found.append(path)
            except OSError:
                pass
    return found


def test_final_state():
    assert os.path.isfile(SOLUTION), f"Solution file {SOLUTION} does not exist or is not a file"
    with open(SOLUTION, "r") as f:
        content = f.read().strip()

    # Preserve the original exact-result assertion.
    assert content == EXPECTED_CONTENT, (
        f"Expected solution content to be {EXPECTED_CONTENT!r}, but got {content!r}"
    )

    key = recover_key_from_history()
    payload = recover_payload_from_wal()
    recovered = xor_plaintext(payload, key).decode()
    assert recovered == EXPECTED_CONTENT, "WAL payload and Git-history key do not yield the expected recovery"
    assert content == recovered, "solution.txt does not contain the value recovered from the WAL and Git history"

    assert os.path.isfile(SOURCE) and not os.path.islink(SOURCE), "decoder.c is missing or is not a regular source file"
    executables = submitted_executables()
    assert executables, "No compiled ELF decoder artifact was left in the profiler_app repository"

    cases = decoder_cases(payload, key)
    working_submitted = []
    for executable in executables:
        try:
            assert_decoder_works(executable, cases)
            working_submitted.append(executable)
        except (AssertionError, OSError):
            pass
    assert working_submitted, "No submitted compiled executable correctly decodes the task and randomized payloads"

    with tempfile.TemporaryDirectory() as tempdir:
        rebuilt = os.path.join(tempdir, "decoder")
        compile_result = subprocess.run(
            ["gcc", "-O2", "-std=c11", SOURCE, "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
        )
        assert compile_result.returncode == 0, (
            "Fixed decoder.c does not compile: "
            + compile_result.stderr.decode(errors="replace")
        )
        assert_decoder_works(rebuilt, cases)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
