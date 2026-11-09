#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import random
import re
import shutil
import stat
import subprocess
import tempfile
import uuid

import pytest

ORACLE_PATH = "/app/legacy_decode"
AGENT_PATH = "/home/user/new_decode"
SOURCE_PATH = "/home/user/new_decode.cpp"
REBUILT_PATH = "/tmp/verifier_new_decode"


def generate_fuzz_input(size):
    key = random.randint(0, 255)
    data = bytearray([key])
    while len(data) < size:
        if random.random() < 0.3:
            count = random.randint(1, 255)
            val = random.randint(0, 255)
            data.extend([0xAA, count, val])
        else:
            val = random.randint(0, 255)
            if val == 0xAA:
                data.extend([0xAA, 1, 0xAA])
            else:
                data.append(val)
    return bytes(data[:size])


def text_section_hash(path, destination):
    subprocess.run(
        ["objcopy", "--dump-section", f".text={destination}", path],
        check=True,
        capture_output=True,
        text=True,
    )
    with open(destination, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


@pytest.fixture(scope="session", autouse=True)
def prepared_artifacts():
    assert os.path.isfile(SOURCE_PATH), f"Missing C++ source: {SOURCE_PATH}"
    assert not os.path.islink(SOURCE_PATH), f"C++ source must be a regular file: {SOURCE_PATH}"
    assert os.path.isfile(AGENT_PATH), f"Missing agent executable: {AGENT_PATH}"
    assert not os.path.islink(AGENT_PATH), f"Agent executable must be a regular file: {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent executable is not executable: {AGENT_PATH}"

    with open(AGENT_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "new_decode must be a compiled ELF executable, not a script"
    elf = subprocess.run(["readelf", "-h", AGENT_PATH], capture_output=True, text=True)
    assert elf.returncode == 0, f"new_decode is not a valid ELF executable: {elf.stderr}"

    with open(AGENT_PATH, "rb") as f:
        agent_bytes = f.read()
    with open(ORACLE_PATH, "rb") as f:
        oracle_bytes = f.read()
    assert agent_bytes != oracle_bytes, "new_decode is a byte-for-byte copy of the legacy decoder"

    with tempfile.TemporaryDirectory() as td:
        agent_text = text_section_hash(AGENT_PATH, os.path.join(td, "agent.text"))
        oracle_text = text_section_hash(ORACLE_PATH, os.path.join(td, "oracle.text"))
        assert agent_text != oracle_text, "new_decode reuses the legacy decoder's executable code"

    compiler = next((p for p in (shutil.which("g++"), shutil.which("c++"), shutil.which("clang++")) if p), None)
    assert compiler is not None, "No C++ compiler is available to verify new_decode.cpp"
    build = subprocess.run(
        [compiler, "-std=c++17", "-O2", SOURCE_PATH, "-o", REBUILT_PATH],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert build.returncode == 0, f"new_decode.cpp does not compile as C++:\n{build.stdout}{build.stderr}"

    random.seed(42)
    cases = []
    for i in range(1000):
        if i % 100 == 0:
            size = random.randint(10000, 100000)
        else:
            size = random.randint(10, 1000)
        cases.append(generate_fuzz_input(size))

    # Include boundary and malformed-tail behavior exercised by the legacy program.
    cases.extend([
        b"",
        b"\x00",
        b"\xff\x00\xff\xaa\x01\xaa",
        b"\x10\xaa",
        b"\x10\xaa\x05",
        b"\x23\xaa\x00\x99",
    ])

    expected = []
    for i, data in enumerate(cases):
        try:
            proc = subprocess.run([ORACLE_PATH], input=data, capture_output=True, timeout=2)
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle timed out on case {i}")
        assert proc.returncode == 0, f"Oracle failed on case {i}"
        expected.append(proc.stdout)

    # The independently rebuilt source and submitted executable are tested while
    # the legacy program is unavailable, preventing wrappers from delegating to it.
    hidden_oracle = f"/tmp/.legacy_decode_hidden_{uuid.uuid4().hex}"
    os.rename(ORACLE_PATH, hidden_oracle)
    try:
        yield {"cases": cases, "expected": expected}
    finally:
        if os.path.exists(hidden_oracle):
            os.rename(hidden_oracle, ORACLE_PATH)
        try:
            os.unlink(REBUILT_PATH)
        except FileNotFoundError:
            pass


def test_backup_profile():
    profile_path = "/home/user/.backup_profile"
    assert os.path.exists(profile_path), f"Missing {profile_path}"

    out = subprocess.check_output(
        f"bash -c 'source {profile_path} && echo $BACKUP_MODE'", shell=True
    ).decode().strip()
    assert out == "RESTORE", f"BACKUP_MODE is '{out}', expected 'RESTORE'"

    out2 = subprocess.check_output(
        f"bash -c 'source {profile_path} && echo $ARCHIVE_ROOT'", shell=True
    ).decode().strip()
    assert out2 == "/tmp/restores", f"ARCHIVE_ROOT is '{out2}', expected '/tmp/restores'"


def test_logrotate_conf():
    conf_path = "/home/user/logrotate.conf"
    assert os.path.exists(conf_path), f"Missing {conf_path}"

    with open(conf_path, "r") as f:
        content = f.read()

    assert "/home/user/restore.log" in content, "logrotate.conf does not target /home/user/restore.log"

    result = subprocess.run(["logrotate", "-d", conf_path], capture_output=True, text=True)
    output = result.stdout + result.stderr
    assert result.returncode == 0, f"logrotate failed to parse config: {output}"

    # Preserve the original content assertions.
    assert "daily" in content, "logrotate.conf missing 'daily'"
    assert "rotate 7" in content, "logrotate.conf missing 'rotate 7'"
    assert "compress" in content, "logrotate.conf missing 'compress'"
    assert "10M" in content and ("size" in content or "maxsize" in content), "logrotate.conf missing size 10M directive"

    # Validate active directives, excluding comments. maxsize is required because
    # plain 'size' overrides rather than supplements a daily schedule.
    clean_lines = []
    for line in content.splitlines():
        line = line.split("#", 1)[0].strip()
        if line:
            clean_lines.append(line)
    clean = "\n".join(clean_lines)

    target = re.search(r'(?:"/home/user/restore\.log"|/home/user/restore\.log)\s*\{(?P<body>.*?)\}', clean, re.S)
    assert target, "No active logrotate stanza targets /home/user/restore.log"

    prefix = clean[:target.start()]
    prefix = re.sub(r'[^\n{}]+\{.*?\}', '', prefix, flags=re.S)
    effective = prefix + "\n" + target.group("body")
    directives = {}
    for line in effective.splitlines():
        parts = line.strip().split()
        if parts and parts[0] not in ("{", "}"):
            directives[parts[0].lower()] = parts[1:]

    assert "daily" in directives and "nodaily" not in directives, "daily rotation is not actively configured"
    assert directives.get("rotate") == ["7"], "active rotate directive must retain exactly 7 backlogs"
    assert "compress" in directives and "nocompress" not in directives, "compression is not actively configured"
    assert directives.get("maxsize") and directives["maxsize"][0].upper() == "10M", \
        "active maxsize directive must be 10M so size can trigger rotation regardless of schedule"


def test_fuzz_equivalence(prepared_artifacts):
    cases = prepared_artifacts["cases"]
    expected = prepared_artifacts["expected"]

    assert os.path.exists(AGENT_PATH), f"Missing agent executable: {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent executable is not executable: {AGENT_PATH}"

    for i, (test_input, oracle_out) in enumerate(zip(cases, expected)):
        for path, label in ((AGENT_PATH, "submitted executable"), (REBUILT_PATH, "rebuilt C++ source")):
            try:
                proc = subprocess.run([path], input=test_input, capture_output=True, timeout=2)
            except subprocess.TimeoutExpired:
                pytest.fail(f"{label} timed out on iteration {i}")
            assert proc.returncode == 0, f"{label} failed on iteration {i}"
            assert proc.stdout == oracle_out, \
                f"Mismatch from {label} on iteration {i} with input size {len(test_input)}"


def test_wrapper_script(prepared_artifacts):
    wrapper_path = "/home/user/restore_wrapper.sh"
    assert os.path.exists(wrapper_path), f"Missing {wrapper_path}"
    assert os.access(wrapper_path, os.X_OK), f"{wrapper_path} is not executable"

    profile_path = "/home/user/.backup_profile"
    log_path = "/home/user/restore.log"
    with open(profile_path, "rb") as f:
        original_profile = f.read()

    old_log_exists = os.path.lexists(log_path)
    old_log = None
    old_mode = None
    if old_log_exists:
        assert os.path.isfile(log_path), "restore.log must be a regular file"
        with open(log_path, "rb") as f:
            old_log = f.read()
        old_mode = stat.S_IMODE(os.stat(log_path).st_mode)
        os.unlink(log_path)

    marker = f"/tmp/profile_sourced_{uuid.uuid4().hex}"
    try:
        with open(profile_path, "ab") as f:
            f.write(f"\nprintf '%s' sourced > {marker!s}\n".encode())

        with tempfile.TemporaryDirectory() as chunk_dir:
            chunks = {
                "alpha.chk": b"\x10\x41",
                "beta.chk": b"\x01\xaa\x03\x40",
            }
            for name, data in chunks.items():
                with open(os.path.join(chunk_dir, name), "wb") as f:
                    f.write(data)
            with open(os.path.join(chunk_dir, "ignore.txt"), "wb") as f:
                f.write(b"must not be processed")

            decoded = {}
            for name, data in chunks.items():
                proc = subprocess.run([REBUILT_PATH], input=data, capture_output=True, check=True)
                decoded[name] = proc.stdout

            run = subprocess.run([wrapper_path, chunk_dir], capture_output=True, timeout=10)
            assert run.returncode == 0, f"restore wrapper failed: {run.stderr.decode(errors='replace')}"
            assert os.path.exists(marker), "restore wrapper did not source /home/user/.backup_profile"

            possible_stdout = {
                decoded["alpha.chk"] + decoded["beta.chk"],
                decoded["beta.chk"] + decoded["alpha.chk"],
            }
            assert run.stdout in possible_stdout, "wrapper did not pass every .chk file through new_decode"

            assert os.path.isfile(log_path), "wrapper did not create /home/user/restore.log"
            with open(log_path, "r", encoding="utf-8") as f:
                lines = f.read().splitlines()
            assert len(lines) == 2, f"expected exactly two appended chunk log lines, got {lines!r}"

            found = {}
            pattern = re.compile(r'^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] Decoded chunk: ([^/]+\.chk) - (\d+) bytes$')
            for line in lines:
                match = pattern.fullmatch(line)
                assert match, f"incorrect restore log format: {line!r}"
                found[match.group(2)] = int(match.group(3))
            assert found == {name: len(data) for name, data in decoded.items()}, \
                f"incorrect filenames or decoded byte counts in restore.log: {found!r}"
    finally:
        with open(profile_path, "wb") as f:
            f.write(original_profile)
        try:
            os.unlink(marker)
        except FileNotFoundError:
            pass
        try:
            os.unlink(log_path)
        except FileNotFoundError:
            pass
        if old_log_exists:
            with open(log_path, "wb") as f:
                f.write(old_log)
            os.chmod(log_path, old_mode)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
