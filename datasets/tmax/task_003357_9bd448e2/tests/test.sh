#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import socket
import struct
import subprocess
import tempfile
import time

import pytest

ROOT = "/home/user/scanner"
SERVER_ADDR = "http://127.0.0.1:50051"


def find_cli():
    for path in (
        f"{ROOT}/target/debug/scanner-cli",
        f"{ROOT}/target/release/scanner-cli",
    ):
        if os.path.isfile(path) and os.access(path, os.X_OK):
            return path
    return None


def find_server():
    candidates = [
        f"{ROOT}/target/debug/scanner",
        f"{ROOT}/target/release/scanner",
        f"{ROOT}/target/debug/scanner-server",
        f"{ROOT}/target/release/scanner-server",
    ]
    for directory in (f"{ROOT}/target/debug", f"{ROOT}/target/release"):
        if os.path.isdir(directory):
            for path in glob.glob(directory + "/*"):
                name = os.path.basename(path)
                if name != "scanner-cli" and not name.endswith((".d", ".rlib", ".rmeta", ".so", ".a")):
                    candidates.append(path)
    for path in candidates:
        if os.path.isfile(path) and os.access(path, os.X_OK):
            return path
    return None


def port_open():
    with socket.socket() as sock:
        sock.settimeout(0.2)
        return sock.connect_ex(("127.0.0.1", 50051)) == 0


@pytest.fixture(scope="session")
def service():
    cli = find_cli()
    assert cli is not None, "scanner-cli binary not found"

    proc = None
    if not port_open():
        server = find_server()
        assert server is not None, "server is not running and no server binary was found"
        proc = subprocess.Popen([server], cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        deadline = time.time() + 8
        while time.time() < deadline and not port_open():
            if proc.poll() is not None:
                break
            time.sleep(0.1)
        assert port_open(), "gRPC server did not bind to 127.0.0.1:50051"

    yield cli
    if proc is not None:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()


def invoke(cli, path):
    result = subprocess.run(
        [cli, SERVER_ADDR, path], capture_output=True, text=True, timeout=5
    )
    assert result.returncode == 0, result.stderr
    assert result.stderr == "", f"unexpected stderr: {result.stderr!r}"
    assert result.stdout in ("SAFE\n", "EVIL\n", "SAFE", "EVIL"), f"unexpected stdout: {result.stdout!r}"
    return result.stdout.strip()


def expected(payload):
    if len(payload) < 4 or payload[:4] != b"PLD\0":
        return "SAFE"
    code = payload[4:]
    return "EVIL" if b"\x0f\x05" in code or b"\xcd\x80" in code else "SAFE"


def test_makefile_builds_real_static_archive():
    subprocess.run(["make", "clean"], cwd="/app/libpld", check=True, capture_output=True)
    subprocess.run(["make"], cwd="/app/libpld", check=True, capture_output=True)
    archive = "/app/libpld/libpld.a"
    assert os.path.isfile(archive)
    listing = subprocess.run(["ar", "t", archive], capture_output=True, text=True)
    assert listing.returncode == 0, "libpld.a is not a standard static archive"
    assert "pld.o" in listing.stdout.splitlines()


def test_project_contains_grpc_and_ffi_integration():
    assert os.path.isfile(f"{ROOT}/Cargo.toml")
    assert os.path.isfile(f"{ROOT}/build.rs")
    protos = glob.glob(f"{ROOT}/**/*.proto", recursive=True)
    assert protos, "protobuf definition missing"
    proto = "\n".join(open(p, errors="ignore").read() for p in protos)
    assert "service Scanner" in proto and "rpc CheckPayload" in proto
    assert "bytes payload" in proto and "bool is_safe" in proto

    rust_files = glob.glob(f"{ROOT}/src/**/*.rs", recursive=True) + [f"{ROOT}/build.rs"]
    source = "\n".join(open(p, errors="ignore").read() for p in rust_files if os.path.isfile(p))
    assert "parse_pld" in source and "free_pld" in source, "Rust service does not use the C parser API"
    assert "50051" in source, "server bind port missing"


def test_original_corpus(service):
    cli = service
    for directory, answer in (("/app/corpus/evil", "EVIL"), ("/app/corpus/clean", "SAFE")):
        files = glob.glob(directory + "/*.pld")
        assert files
        for path in files:
            assert invoke(cli, path) == answer


def test_generated_payloads_from_unpredictable_paths(service):
    cli = service
    rng = random.SystemRandom()
    cases = []

    # Invalid PLD inputs are safe even when syscall bytes occur outside parsed code.
    cases.extend([b"", b"P", b"PLD", b"NOPE" + b"\x0f\x05", b"XYZ\0" + b"\xcd\x80"])
    # Boundary and adjacency cases force scanning of only the parsed code buffer.
    cases.extend([
        b"PLD\0",
        b"PLD\0\x0f",
        b"PLD\0\x05",
        b"PLD\0\xcd",
        b"PLD\0\x80",
        b"PLD\x0f\x05",
        b"PLD\0\x0f\x04\x05",
        b"PLD\0\xcd\x81\x80",
        b"PLD\0\x90\x0f\x05\x90",
        b"PLD\0\x90\xcd\x80\x90",
    ])

    forbidden = (b"\x0f\x05", b"\xcd\x80")
    for _ in range(20):
        code = bytearray(rng.randrange(0, 256) for _ in range(rng.randrange(1, 96)))
        # Remove accidental signatures, then optionally insert one at a random location.
        for sig in forbidden:
            while sig in code:
                i = code.find(sig)
                code[i + 1] ^= 1
        if rng.randrange(2):
            sig = forbidden[rng.randrange(2)]
            pos = rng.randrange(len(code) + 1)
            code[pos:pos] = sig
        cases.append(b"PLD\0" + bytes(code))

    with tempfile.TemporaryDirectory(prefix="scanner-hidden-") as td:
        rng.shuffle(cases)
        for i, payload in enumerate(cases):
            # Names carry no class information and vary each run.
            path = os.path.join(td, f"{rng.getrandbits(64):016x}-{i}.bin")
            with open(path, "wb") as f:
                f.write(payload)
            assert invoke(cli, path) == expected(payload), f"misclassified generated case {i}"


def test_cli_really_contacts_server(service):
    cli = service
    # A valid client must fail rather than classify locally when directed to an unused endpoint.
    with tempfile.NamedTemporaryFile(suffix=".pld") as f:
        f.write(b"PLD\0\x90\x90")
        f.flush()
        result = subprocess.run(
            [cli, "http://127.0.0.1:59999", f.name],
            capture_output=True, text=True, timeout=5
        )
    assert result.returncode != 0 or result.stdout.strip() not in ("SAFE", "EVIL"), \
        "scanner-cli appears to classify locally instead of using gRPC"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
