#!/bin/bash
set -e
mkdir -p /logs/verifier
export RUSTUP_HOME=/usr/local/rustup
export CARGO_HOME=/usr/local/cargo
export PATH=/usr/local/cargo/bin:$PATH

cat <<'TEST_EOF' > /tmp/test_final_state.py
import collections
import concurrent.futures
import hashlib
import json
import os
import re
import struct
import subprocess
import time
import urllib.error
import urllib.request

PROJECT = "/home/user/data_api"
PROCESSOR = os.path.join(PROJECT, "src/processor.rs")
BINARY = os.path.join(PROJECT, "target/x86_64-unknown-linux-musl/release/data_api")
LOG = "/home/user/result.log"
TARGET = "x86_64-unknown-linux-musl"


def run(cmd, **kwargs):
    return subprocess.run(cmd, cwd=PROJECT, capture_output=True, text=True, timeout=300, **kwargs)


def request(method, path, payload=None):
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        "http://127.0.0.1:3000" + path,
        data=data,
        method=method,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=10) as response:
        return response.status, json.loads(response.read().decode("utf-8"))


def assert_method_rejected(method, path):
    try:
        request(method, path)
    except urllib.error.HTTPError as exc:
        assert exc.code == 405, f"{method} {path} returned {exc.code}, expected 405"
    else:
        raise AssertionError(f"{method} {path} unexpectedly succeeded")


def mutated_processor(source):
    start = source.find("pub fn process_string")
    assert start >= 0, "process_string is missing"
    brace = source.find("{", start)
    assert brace >= 0, "process_string has no body"
    depth = 0
    end = None
    for index in range(brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                end = index + 1
                break
    assert end is not None, "could not locate the end of process_string"
    replacement = "pub fn process_string(input: &str) -> String {\n    input.chars().chain(std::iter::once('\\0')).collect()\n}"
    return source[:start] + replacement + source[end:]


def assert_static_x86_64_elf(path):
    assert os.path.isfile(path), f"Musl binary not found at {path}"
    assert os.access(path, os.X_OK), "Musl artifact is not executable"
    with open(path, "rb") as handle:
        data = handle.read()
    assert data[:4] == b"\x7fELF", "Musl artifact is not an ELF executable"
    assert data[4] == 2 and data[5] == 1, "Musl artifact is not 64-bit little-endian ELF"
    assert struct.unpack_from("<H", data, 18)[0] == 62, "ELF is not for x86_64"
    phoff = struct.unpack_from("<Q", data, 32)[0]
    phentsize = struct.unpack_from("<H", data, 54)[0]
    phnum = struct.unpack_from("<H", data, 56)[0]
    types = [struct.unpack_from("<I", data, phoff + i * phentsize)[0] for i in range(phnum)]
    assert 3 not in types, "Musl binary unexpectedly contains a dynamic interpreter"


def test_complete_task():
    # Preserve the original compile-and-test assertion.
    tested = run(["cargo", "test"])
    assert tested.returncode == 0, f"cargo test failed:\n{tested.stderr}\n{tested.stdout}"

    assert os.path.isfile(PROCESSOR), f"{PROCESSOR} does not exist"
    with open(PROCESSOR, encoding="utf-8") as handle:
        source = handle.read()
    # Preserve the original source assertions and tie the requested name to the macro.
    assert "proptest_length_invariant" in source, "proptest_length_invariant is not found in processor.rs"
    assert "proptest!" in source, "proptest macro is not used in processor.rs"
    assert re.search(r"proptest!\s*\{[\s\S]*?fn\s+proptest_length_invariant\b", source), \
        "proptest_length_invariant is not defined by a proptest! block"

    listed = run(["cargo", "test", "--", "--list"])
    assert listed.returncode == 0, listed.stderr
    assert re.search(r"(?:^|::)proptest_length_invariant: test$", listed.stdout, re.MULTILINE), \
        "the named property test is not registered"

    # Mutation-test the property: every generated input must detect an output with one extra character.
    try:
        with open(PROCESSOR, "w", encoding="utf-8") as handle:
            handle.write(mutated_processor(source))
        mutation = run(["cargo", "test", "proptest_length_invariant", "--", "--nocapture"])
    finally:
        with open(PROCESSOR, "w", encoding="utf-8") as handle:
            handle.write(source)
    mutation_output = mutation.stdout + mutation.stderr
    assert mutation.returncode != 0, "property test passed despite a guaranteed character-length violation"
    assert "could not compile" not in mutation_output, f"mutation only caused a compile error:\n{mutation_output}"
    assert "proptest_length_invariant" in mutation_output and "FAILED" in mutation_output, \
        f"the named property test did not fail on the length violation:\n{mutation_output}"

    installed = subprocess.run(
        ["rustup", "target", "list", "--installed"], capture_output=True, text=True, timeout=60
    )
    assert installed.returncode == 0 and TARGET in installed.stdout.split(), f"{TARGET} is not installed"

    # Actually perform the required cross-compilation rather than trusting an existing file.
    built = run(["cargo", "build", "--target", TARGET, "--release"])
    assert built.returncode == 0, f"musl build failed:\n{built.stderr}\n{built.stdout}"
    assert_static_x86_64_elf(BINARY)

    # Execute the resulting artifact and verify endpoint methods, Unicode behavior, and shared history.
    subprocess.run(["pkill", "-f", BINARY], capture_output=True)
    server = subprocess.Popen([BINARY], cwd=PROJECT, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    try:
        for _ in range(50):
            if server.poll() is not None:
                raise AssertionError(f"server exited early: {server.stderr.read().decode(errors='replace')}")
            try:
                status, body = request("GET", "/history")
                if status == 200:
                    break
            except Exception:
                time.sleep(0.1)
        else:
            raise AssertionError("musl API server did not become ready")

        assert body == [], f"initial history should be empty, got {body!r}"
        assert_method_rejected("GET", "/process")
        assert_method_rejected("POST", "/history")

        text = "é🙂abcdefghiXYZ"
        status, result = request("POST", "/process", {"text": text})
        assert status == 200
        assert result == {"processed": text[::-1], "summary": "".join(list(text)[:10])}, result
        status, history = request("GET", "/history")
        assert status == 200 and history == [text[::-1]], history

        values = [f"item-{i}" for i in range(16)]
        def post_value(value):
            status, result = request("POST", "/process", {"text": value})
            assert status == 200
            assert result == {"processed": value[::-1], "summary": value}
            return value[::-1]

        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            expected_added = list(pool.map(post_value, values))
        _, history = request("GET", "/history")
        assert len(history) == 1 + len(values), "shared history lost concurrent updates"
        assert history[0] == text[::-1]
        assert collections.Counter(history[1:]) == collections.Counter(expected_added)
    finally:
        server.terminate()
        try:
            server.wait(timeout=5)
        except subprocess.TimeoutExpired:
            server.kill()
            server.wait()

    # Preserve and strengthen the original result.log assertions.
    assert os.path.isfile(LOG), f"{LOG} does not exist"
    with open(LOG, encoding="utf-8") as handle:
        lines = handle.read().splitlines()
    assert len(lines) == 3, f"result.log must contain exactly 3 lines, found {len(lines)}"
    assert lines[0] == "TESTS_PASSED", f"Line 1 should be 'TESTS_PASSED', found {lines[0]!r}"
    assert lines[1] == "BUILD_MUSL_PASSED", f"Line 2 should be 'BUILD_MUSL_PASSED', found {lines[1]!r}"
    with open(BINARY, "rb") as handle:
        expected_hash = hashlib.sha256(handle.read()).hexdigest()
    assert lines[2] == expected_hash, f"Line 3 checksum mismatch. Expected {expected_hash}, found {lines[2]!r}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
