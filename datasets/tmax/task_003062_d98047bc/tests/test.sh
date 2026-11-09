#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import difflib
import os
import re
import shutil
import struct
import subprocess
import tempfile
import uuid
import wave

import pytest

HOME = "/home/user"
EXTRACT_SRC = f"{HOME}/extract.c"
SANDBOX_SRC = f"{HOME}/sandbox.c"
EXTRACT_BIN = "/tmp/submitted_extract"
SANDBOX_BIN = "/tmp/submitted_sandbox"
WAV = "/app/exfil_audio.wav"
PROBE = "/app/backdoor_probe"
RECOVERED = f"{HOME}/recovered_traffic.log"
SANDBOX_OUTPUT = f"{HOME}/sandbox_output.txt"


def run(cmd, timeout=15):
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          timeout=timeout, check=False)


def compile_submission(source, output, extra=()):
    assert os.path.isfile(source), f"Missing required C source: {source}"
    result = run(["gcc", "-std=c11", "-Wall", "-Wextra", "-Werror",
                  source, "-o", output, *extra], timeout=30)
    assert result.returncode == 0, (
        f"Failed to compile {source}:\n{result.stdout.decode(errors='replace')}"
        f"{result.stderr.decode(errors='replace')}"
    )


def make_wav(path, message):
    bits = [(byte >> bit) & 1 for byte in message + b"\0" for bit in range(8)]
    samples = [0] * max(4096, len(bits) + 32)
    for index, bit in enumerate(bits):
        samples[index] = bit
    with wave.open(path, "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(44100)
        output.writeframes(b"".join(struct.pack("<h", sample) for sample in samples))


def make_probe(path, initial, syscall_number, survived=b"SURVIVED_FORBIDDEN_SYSCALL\n"):
    payload = initial
    assembly = f'''\n.global _start\n.section .text\n_start:\n    mov $1, %rax\n    mov $1, %rdi\n    lea first(%rip), %rsi\n    mov ${len(payload)}, %rdx\n    syscall\n    mov ${syscall_number}, %rax\n    xor %rdi, %rdi\n    xor %rsi, %rsi\n    xor %rdx, %rdx\n    xor %r10, %r10\n    xor %r8, %r8\n    xor %r9, %r9\n    syscall\n    mov $1, %rax\n    mov $1, %rdi\n    lea survived(%rip), %rsi\n    mov ${len(survived)}, %rdx\n    syscall\n    mov $60, %rax\n    xor %rdi, %rdi\n    syscall\n.section .rodata\nfirst:\n    .byte {','.join(str(x) for x in payload)}\nsurvived:\n    .byte {','.join(str(x) for x in survived)}\n'''
    source = "/tmp/verifier_probe.S"
    with open(source, "w") as handle:
        handle.write(assembly)
    result = run(["gcc", "-nostdlib", "-static", source, "-o", path], timeout=30)
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    os.chmod(path, 0o755)


def make_allowed_probe(path, initial):
    after = b"ALLOWED_AFTER_BRK\n"
    assembly = f'''\n.global _start\n.section .text\n_start:\n    mov $1, %rax\n    mov $1, %rdi\n    lea first(%rip), %rsi\n    mov ${len(initial)}, %rdx\n    syscall\n    mov $12, %rax\n    xor %rdi, %rdi\n    syscall\n    mov $1, %rax\n    mov $1, %rdi\n    lea after(%rip), %rsi\n    mov ${len(after)}, %rdx\n    syscall\n    mov $60, %rax\n    xor %rdi, %rdi\n    syscall\n.section .rodata\nfirst:\n    .byte {','.join(str(x) for x in initial)}\nafter:\n    .byte {','.join(str(x) for x in after)}\n'''
    source = "/tmp/verifier_allowed_probe.S"
    with open(source, "w") as handle:
        handle.write(assembly)
    result = run(["gcc", "-nostdlib", "-static", source, "-o", path], timeout=30)
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    os.chmod(path, 0o755)


def run_sandbox_and_read():
    try:
        os.unlink(SANDBOX_OUTPUT)
    except FileNotFoundError:
        pass
    result = run([SANDBOX_BIN], timeout=10)
    assert os.path.isfile(SANDBOX_OUTPUT), (
        "The sandbox did not create /home/user/sandbox_output.txt. "
        f"stderr: {result.stderr.decode(errors='replace')}"
    )
    with open(SANDBOX_OUTPUT, "rb") as handle:
        return handle.read()


@pytest.fixture(scope="session", autouse=True)
def validate_programs():
    compile_submission(EXTRACT_SRC, EXTRACT_BIN)
    compile_submission(SANDBOX_SRC, SANDBOX_BIN, ("-lseccomp",))

    with open(SANDBOX_SRC, "r", errors="replace") as handle:
        sandbox_source = handle.read()
    assert re.search(r"\bfork\s*\(", sandbox_source), "sandbox.c must fork a child"
    assert re.search(r"\b(execve|execl|execlp|execv|execvp)\s*\(", sandbox_source), \
        "sandbox.c must execute /app/backdoor_probe"
    assert "seccomp" in sandbox_source.lower(), "sandbox.c does not appear to use seccomp"
    assert PROBE in sandbox_source, "sandbox.c must execute /app/backdoor_probe"

    wav_backup = "/tmp/original_exfil_audio.wav"
    probe_backup = "/tmp/original_backdoor_probe"
    shutil.copy2(WAV, wav_backup)
    shutil.copy2(PROBE, probe_backup)

    try:
        token = uuid.uuid4().hex.encode("ascii")
        challenge = (b"GET /audit/" + token + b" HTTP/1.1\r\n"
                     b"Host: verifier.invalid\r\n"
                     b"Cookie: challenge=" + token + b"\r\n\r\n")
        make_wav(WAV, challenge)
        try:
            os.unlink(RECOVERED)
        except FileNotFoundError:
            pass
        result = run([EXTRACT_BIN], timeout=10)
        assert result.returncode == 0, result.stderr.decode(errors="replace")
        assert os.path.isfile(RECOVERED), "extract.c did not create recovered_traffic.log"
        with open(RECOVERED, "rb") as handle:
            actual = handle.read()
        assert actual == challenge, "extract.c failed a verifier-generated WAV message"

        # Exercise a permitted syscall after exec so a sandbox that simply kills
        # every child does not pass.
        allowed_initial = b"Probe started.\n" + uuid.uuid4().hex.encode() + b"\n"
        make_allowed_probe(PROBE, allowed_initial)
        output = run_sandbox_and_read()
        assert allowed_initial in output and b"ALLOWED_AFTER_BRK\n" in output, \
            "The sandbox killed or failed to execute a probe using permitted syscalls"

        # Each probe prints an unpredictable marker, then invokes a forbidden
        # syscall. The post-syscall marker must be unreachable under KILL policy.
        for syscall_number in (2, 39, 41):  # open, getpid, socket on x86-64
            initial = b"Probe started.\n" + uuid.uuid4().hex.encode() + b"\n"
            make_probe(PROBE, initial, syscall_number)
            output = run_sandbox_and_read()
            assert initial in output, "The sandbox did not execute and capture the test probe"
            assert b"SURVIVED_FORBIDDEN_SYSCALL" not in output, \
                f"Probe survived forbidden syscall number {syscall_number}"

    finally:
        shutil.copy2(wav_backup, WAV)
        shutil.copy2(probe_backup, PROBE)

    # Generate the required final artifacts using the submitted programs and the
    # real task inputs before retaining the original final-state assertions.
    result = run([EXTRACT_BIN], timeout=10)
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    run_sandbox_and_read()


def test_recovered_traffic_metric():
    """Check that the recovered traffic log matches the expected text with high similarity."""
    expected = "GET /admin/dashboard HTTP/1.1\r\nHost: internal.corp\r\nCookie: auth_token=admin_bypass_9921; role=superuser\r\nUser-Agent: Mozilla/5.0\r\n\r\n"
    target_file = "/home/user/recovered_traffic.log"

    assert os.path.exists(target_file), f"File not found: {target_file}"

    with open(target_file, "r") as f:
        actual = f.read()

    ratio = difflib.SequenceMatcher(None, expected, actual).ratio()
    threshold = 0.95
    assert ratio >= threshold, f"String similarity metric {ratio:.4f} is below the threshold of {threshold}. Actual content: {repr(actual)}"


def test_malicious_cookie():
    """Check that the malicious cookie was correctly identified."""
    target_file = "/home/user/malicious_cookie.txt"
    expected_cookie = "Cookie: auth_token=admin_bypass_9921; role=superuser"

    assert os.path.exists(target_file), f"File not found: {target_file}"

    with open(target_file, "r") as f:
        actual = f.read().strip()

    assert expected_cookie in actual, f"Expected cookie not found in {target_file}. Found: {actual}"


def test_sandbox_output():
    """Check that the sandbox successfully isolated the process and captured its initial output."""
    target_file = "/home/user/sandbox_output.txt"

    assert os.path.exists(target_file), f"File not found: {target_file}"

    with open(target_file, "r") as f:
        actual = f.read()

    assert "Probe started." in actual, f"Expected initial output 'Probe started.' not found in {target_file}."
    assert "Error:" not in actual, f"Sandbox failed to kill the process on illegal syscall. Output contained: {actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
