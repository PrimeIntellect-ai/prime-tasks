#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import random
import stat
import string
import subprocess
import tempfile


def expected_sanitize(data):
    out = bytearray()
    i = 0
    hexdigits = b"0123456789abcdefABCDEF"
    while i < len(data):
        if i + 2 < len(data) and data[i] == ord('%') and data[i + 1] in hexdigits and data[i + 2] in hexdigits:
            out.append(int(data[i + 1:i + 3], 16))
            i += 3
        else:
            out.append(data[i])
            i += 1
    return bytes(out).replace(b"<script>", b"")


def run_checked(path, data):
    return subprocess.run([path], input=data, capture_output=True, timeout=10)


def test_built_from_repaired_source_and_standalone_behavior():
    source = "/home/user/sanitizer_draft.c"
    agent_bin = "/home/user/sanitizer_fixed"
    assert os.path.isfile(source), f"Missing repaired source: {source}"
    assert os.path.isfile(agent_bin), f"Missing fixed binary: {agent_bin}"
    assert os.access(agent_bin, os.X_OK), f"Fixed binary is not executable: {agent_bin}"

    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "sanitizer_rebuilt")
        build = subprocess.run(["gcc", "-O2", source, "-o", rebuilt], capture_output=True)
        assert build.returncode == 0, f"Repaired source does not compile with gcc -O2: {build.stderr.decode(errors='replace')}"

        # Compare executable code rather than complete ELF files so harmless strip/build
        # metadata differences are allowed while still requiring the submitted program
        # to have been compiled from the submitted repaired source.
        rebuilt_text = os.path.join(td, "rebuilt.text")
        agent_text = os.path.join(td, "agent.text")
        for binary, output in ((rebuilt, rebuilt_text), (agent_bin, agent_text)):
            result = subprocess.run(["objcopy", f"--dump-section", f".text={output}", binary], capture_output=True)
            assert result.returncode == 0 and os.path.isfile(output), f"Not a valid compiled executable: {binary}"
        with open(rebuilt_text, "rb") as f:
            expected_text = f.read()
        with open(agent_text, "rb") as f:
            submitted_text = f.read()
        assert submitted_text == expected_text, "sanitizer_fixed was not compiled from the submitted repaired source with gcc -O2"

        with open(agent_bin, "rb") as f:
            agent_bytes = f.read()
        with open("/app/legacy_sanitizer", "rb") as f:
            oracle_bytes = f.read()
        assert agent_bytes != oracle_bytes, "sanitizer_fixed is a byte-identical copy of the legacy binary"

        cases = [
            b"",
            b"plain text",
            b"%",
            b"%A",
            b"%GG",
            b"abc%41def",
            b"<script>alert(1)</script>",
            b"<script><script>x<script>",
            b"%3Cscript%3Epayload",
            b"prefix%4Zsuffix%",
            (b"A" * 10000) + b"<script>" + (b"B" * 10000) + b"%Q",
        ]

        # Make the legacy executable unavailable while exercising the independent
        # rebuild, so an exec-wrapper around /app/legacy_sanitizer cannot pass.
        oracle = "/app/legacy_sanitizer"
        hidden = "/app/.legacy_sanitizer.verifier-hidden"
        assert not os.path.exists(hidden)
        os.rename(oracle, hidden)
        try:
            for data in cases:
                proc = run_checked(rebuilt, data)
                assert proc.returncode == 0, f"Rebuilt sanitizer failed on {data[:80]!r}: {proc.stderr!r}"
                assert proc.stdout == expected_sanitize(data), f"Rebuilt sanitizer produced wrong output on {data[:80]!r}"
        finally:
            os.rename(hidden, oracle)


def _write_ci_probe(path, log_path):
    probe = f'''#!/usr/bin/python3
import base64
import os
import sys

data = sys.stdin.buffer.read()
with open({log_path!r}, "ab") as log:
    log.write(base64.b64encode(data) + b"\\n")

hexchars = b"0123456789abcdefABCDEF"
out = bytearray()
i = 0
while i < len(data):
    if i + 2 < len(data) and data[i] == 37 and data[i+1] in hexchars and data[i+2] in hexchars:
        out.append(int(data[i+1:i+3], 16))
        i += 3
    else:
        out.append(data[i])
        i += 1
result = bytes(out).replace(b"<script>", b"")
target = os.environ.get("VERIFIER_CORRUPT_INPUT")
if target is not None and data == base64.b64decode(target):
    result += b"VERIFIER_WRONG_OUTPUT"
sys.stdout.buffer.write(result)
'''
    with open(path, "w") as f:
        f.write(probe)
    os.chmod(path, 0o755)


def _read_probe_log(path):
    if not os.path.exists(path):
        return []
    with open(path, "rb") as f:
        return [base64.b64decode(line.strip()) for line in f if line.strip()]


def _is_malformed_percent(data):
    hexdigits = b"0123456789abcdefABCDEF"
    for i, value in enumerate(data):
        if value == ord('%') and not (i + 2 < len(data) and data[i + 1] in hexdigits and data[i + 2] in hexdigits):
            return True
    return False


def test_ci_test_script():
    ci_script = "/home/user/ci_test.sh"
    agent_bin = "/home/user/sanitizer_fixed"
    assert os.path.exists(ci_script), f"Missing CI script: {ci_script}"
    assert os.path.isfile(ci_script), f"Not a file: {ci_script}"
    assert os.access(ci_script, os.X_OK), f"CI script is not executable: {ci_script}"

    result = subprocess.run([ci_script], capture_output=True, timeout=20)
    assert result.returncode == 0, f"CI script failed with exit code {result.returncode}. Stderr: {result.stderr.decode(errors='replace')}"

    backup = "/home/user/.sanitizer_fixed.verifier-backup"
    assert not os.path.exists(backup)
    with tempfile.TemporaryDirectory() as td:
        log_path = os.path.join(td, "calls.log")
        os.rename(agent_bin, backup)
        try:
            _write_ci_probe(agent_bin, log_path)
            env = os.environ.copy()
            env.pop("VERIFIER_CORRUPT_INPUT", None)
            discovery = subprocess.run([ci_script], capture_output=True, env=env, timeout=20)
            assert discovery.returncode == 0, "CI tests reject correct sanitizer output"
            calls = _read_probe_log(log_path)
            assert len(calls) >= 3, "CI script must run sanitizer_fixed at least three times"
            distinct = list(dict.fromkeys(calls))
            assert len(distinct) >= 3, "CI script must contain at least three distinct test payloads"
            assert any(b"<script>" in payload for payload in distinct), "CI script lacks a malicious <script> payload"
            assert any(_is_malformed_percent(payload) for payload in distinct), "CI script lacks a malformed % payload"

            # Every discovered hardcoded case must actually compare against an
            # expected value: selectively corrupting its output must make CI fail.
            for payload in distinct:
                open(log_path, "wb").close()
                bad_env = env.copy()
                bad_env["VERIFIER_CORRUPT_INPUT"] = base64.b64encode(payload).decode("ascii")
                bad = subprocess.run([ci_script], capture_output=True, env=bad_env, timeout=20)
                assert bad.returncode == 1, f"CI script did not detect wrong output for payload {payload!r}"
        finally:
            if os.path.exists(agent_bin):
                os.unlink(agent_bin)
            os.rename(backup, agent_bin)


def generate_fuzz_input(length):
    printable = string.printable.encode('ascii')
    patterns = [b"%", b"%A", b"%1B", b"<script>", b"<<script>script>"]
    out = bytearray()
    while len(out) < length:
        r = random.random()
        if r < 0.7:
            out.append(random.choice(printable))
        elif r < 0.85:
            out.append(random.randint(0, 255))
        else:
            out.extend(random.choice(patterns))
    return bytes(out[:length])


def test_fuzz_equivalence():
    oracle_bin = "/app/legacy_sanitizer"
    agent_bin = "/home/user/sanitizer_fixed"

    assert os.path.exists(agent_bin), f"Missing fixed binary: {agent_bin}"
    assert os.access(agent_bin, os.X_OK), f"Fixed binary is not executable: {agent_bin}"
    assert os.path.exists(oracle_bin), f"Missing oracle binary: {oracle_bin}"
    assert os.access(oracle_bin, os.X_OK), f"Oracle binary is not executable: {oracle_bin}"

    random.seed(42)
    N = 10000
    for i in range(N):
        length = random.randint(0, 4096)
        if random.random() < 0.9:
            length = random.randint(0, 128)
        test_input = generate_fuzz_input(length)
        oracle_proc = subprocess.run([oracle_bin], input=test_input, capture_output=True)
        agent_proc = subprocess.run([agent_bin], input=test_input, capture_output=True)
        assert oracle_proc.returncode == agent_proc.returncode, \
            f"Exit code mismatch on input {test_input[:100]!r}... Oracle: {oracle_proc.returncode}, Agent: {agent_proc.returncode}"
        assert oracle_proc.stdout == agent_proc.stdout, \
            f"Output mismatch on input {test_input[:100]!r}... Oracle: {oracle_proc.stdout[:100]!r}, Agent: {agent_proc.stdout[:100]!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
