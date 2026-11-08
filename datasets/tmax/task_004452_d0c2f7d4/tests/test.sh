#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import secrets
import struct
import subprocess
import tempfile
import uuid
import pytest

EXECUTABLE = "/app/build/config_filter"
LIBRARY = "/app/lib/libasm_checker.so"
MIN_VERSION = "1.4.2-rc.1"
WS_ENDPOINT = "ws://secure.local:8080"
MAGIC = 0xCAFEBABE
SEMVER = re.compile(
    r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
    r"(?:-((?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)(?:\.(?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*))*))?"
    r"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$"
)


def parse_semver(value):
    if not isinstance(value, str):
        return None
    match = SEMVER.fullmatch(value)
    if not match:
        return None
    prerelease = None if match.group(4) is None else match.group(4).split(".")
    return (int(match.group(1)), int(match.group(2)), int(match.group(3)), prerelease)


def compare_semver(left, right):
    for i in range(3):
        if left[i] != right[i]:
            return 1 if left[i] > right[i] else -1
    lp, rp = left[3], right[3]
    if lp is None or rp is None:
        if lp is None and rp is None:
            return 0
        return 1 if lp is None else -1
    for a, b in zip(lp, rp):
        if a == b:
            continue
        a_num, b_num = a.isdigit(), b.isdigit()
        if a_num and b_num:
            return 1 if int(a) > int(b) else -1
        if a_num != b_num:
            return -1 if a_num else 1
        return 1 if a > b else -1
    return (len(lp) > len(rp)) - (len(lp) < len(rp))


def expected_clean(raw):
    try:
        obj = json.loads(raw)
    except (json.JSONDecodeError, UnicodeDecodeError):
        return False
    if not isinstance(obj, dict):
        return False
    version = parse_semver(obj.get("version"))
    minimum = parse_semver(MIN_VERSION)
    magic = obj.get("magic_code")
    return (
        version is not None
        and compare_semver(version, minimum) >= 0
        and obj.get("ws_endpoint") == WS_ENDPOINT
        and isinstance(magic, int)
        and not isinstance(magic, bool)
        and magic == MAGIC
    )


def run_filter(path):
    return subprocess.run(
        [EXECUTABLE, path], capture_output=True, timeout=5, check=False
    ).returncode


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} not found. Did you build it?"
    assert os.access(EXECUTABLE, os.X_OK), f"{EXECUTABLE} is not executable."


def test_required_shared_library_and_linkage():
    assert os.path.isfile(LIBRARY), f"Required shared library {LIBRARY} is missing"
    with open(LIBRARY, "rb") as handle:
        header = handle.read(20)
    assert header[:4] == b"\x7fELF", f"{LIBRARY} is not an ELF library"
    byte_order = "<" if header[5] == 1 else ">"
    assert struct.unpack(byte_order + "H", header[16:18])[0] == 3, f"{LIBRARY} is not a shared object"

    linked = subprocess.run(["ldd", EXECUTABLE], text=True, capture_output=True, timeout=5)
    output = linked.stdout + linked.stderr
    assert linked.returncode == 0, output
    assert "libasm_checker.so" in output, "config_filter is not linked to libasm_checker.so"
    assert not any("libasm_checker.so" in line and "not found" in line for line in output.splitlines()), output

    with open("/app/CMakeLists.txt", encoding="utf-8", errors="replace") as handle:
        cmake = handle.read()
    assert "target_link_libraries" in cmake and "asm_checker" in cmake, \
        "CMakeLists.txt does not link config_filter against asm_checker"


def test_adversarial_corpus():
    clean_dir = "/app/hidden_clean"
    evil_dir = "/app/hidden_evil"
    assert os.path.isdir(clean_dir), f"Directory {clean_dir} missing"
    assert os.path.isdir(evil_dir), f"Directory {evil_dir} missing"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir)
                   if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir)
                  if os.path.isfile(os.path.join(evil_dir, f))]

    failed_clean = [os.path.basename(p) for p in clean_files if run_filter(p) != 0]
    failed_evil = [os.path.basename(p) for p in evil_files if run_filter(p) == 0]
    errors = []
    if failed_evil:
        errors.append(f"{len(failed_evil)} of {len(evil_files)} evil bypassed: {', '.join(failed_evil)}")
    if failed_clean:
        errors.append(f"{len(failed_clean)} of {len(clean_files)} clean modified: {', '.join(failed_clean)}")
    assert not errors, " | ".join(errors)


def test_generated_rule_corpus():
    nonce = secrets.token_hex(8)
    valid = lambda version=MIN_VERSION, endpoint=WS_ENDPOINT, magic=MAGIC, **extra: {
        "version": version, "ws_endpoint": endpoint, "magic_code": magic, **extra
    }

    objects = [
        valid(),
        valid(version="1.4.2-rc.1+build.77", extra_field=nonce),
        valid(version="1.4.2-rc.2"),
        valid(version="1.4.2"),
        valid(version="1.4.3-alpha"),
        valid(version="2.0.0"),
        valid(version="1.4.2-beta.99"),
        valid(version="1.4.2-rc"),
        valid(version="1.4.2-rc.0"),
        valid(version="1.4.1"),
        valid(version="0.99.99"),
        valid(version="01.4.2"),
        valid(version="1.04.2"),
        valid(version="1.4.02"),
        valid(version="v1.4.2"),
        valid(version="1.4"),
        valid(version="1.4.2-01"),
        valid(version="1.4.2-rc..1"),
        valid(version=1.5),
        valid(endpoint="wss://secure.local:8080"),
        valid(endpoint="ws://evil.local:8080"),
        valid(endpoint="ws://secure.local:8081"),
        valid(endpoint="ws://secure.local:80800"),
        valid(endpoint="ws://secure.local:8080/path"),
        valid(endpoint="ws://secure.local:8080?port=8080"),
        valid(magic=0),
        valid(magic=MAGIC - 1),
        valid(magic=True),
        valid(magic=str(MAGIC)),
        {"version": "2.0.0", "ws_endpoint": WS_ENDPOINT},
        {"version": "2.0.0", "magic_code": MAGIC},
        {"ws_endpoint": WS_ENDPOINT, "magic_code": MAGIC},
        [],
        None,
    ]

    for _ in range(8):
        objects.append(valid(version=f"{secrets.randbelow(20) + 2}.{secrets.randbelow(30)}.{secrets.randbelow(30)}"))
        objects.append(valid(version=f"1.{secrets.randbelow(4)}.{secrets.randbelow(30)}"))
        bad_magic = secrets.randbelow(2**31)
        objects.append(valid(magic=bad_magic))

    cases = [json.dumps(obj, separators=(",", ":")) for obj in objects]
    cases.extend(["", "{", "not json", '{"version":"2.0.0",', "[1,2,3]"])
    random.SystemRandom().shuffle(cases)

    directory = tempfile.mkdtemp(prefix=f"cfgcase_{uuid.uuid4().hex}_")
    path = os.path.join(directory, f"input_{uuid.uuid4().hex}.json")
    failures = []
    for index, raw in enumerate(cases):
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(raw)
        expected = 0 if expected_clean(raw) else 1
        actual = run_filter(path)
        if actual != expected:
            failures.append(f"case {index}: expected exit {expected}, got {actual}, input={raw!r}")
    assert not failures, "\n".join(failures[:10])
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
