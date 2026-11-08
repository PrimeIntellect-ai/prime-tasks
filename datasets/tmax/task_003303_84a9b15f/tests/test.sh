#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import http.client
import json
import os
import random
import shutil
import subprocess
import tempfile

import pytest

PROJECT = "/home/user/project"
SO_PATH = os.path.join(PROJECT, "libchecksum.so")
URL_HOST = "127.0.0.1"
URL_PORT = 8080
SEED = 583


def load_and_check_library(path):
    lib = ctypes.CDLL(path)

    asm = lib.asm_checksum
    asm.argtypes = [ctypes.POINTER(ctypes.c_uint8), ctypes.c_size_t, ctypes.c_uint32]
    asm.restype = ctypes.c_uint32

    wrapper = lib.compute_checksum
    wrapper.argtypes = [ctypes.POINTER(ctypes.c_uint8), ctypes.c_size_t, ctypes.c_uint32]
    wrapper.restype = ctypes.c_uint32

    rng = random.SystemRandom()
    cases = [(b"", 0), (b"hello", 583), (bytes(range(256)), 0xFFFFFF00)]
    for _ in range(20):
        cases.append((os.urandom(rng.randrange(0, 2049)), rng.randrange(0, 2**32)))

    for data, seed in cases:
        storage = ctypes.create_string_buffer(data if data else b"\0")
        ptr = ctypes.cast(storage, ctypes.POINTER(ctypes.c_uint8))
        expected = (seed + sum(data)) & 0xFFFFFFFF
        assert asm(ptr, len(data), seed) == expected
        assert wrapper(ptr, len(data), seed) == expected


def post_compute(version, body):
    conn = http.client.HTTPConnection(URL_HOST, URL_PORT, timeout=3)
    try:
        conn.request(
            "POST",
            "/compute",
            body=body,
            headers={"X-Client-Version": version, "Content-Type": "application/octet-stream"},
        )
        response = conn.getresponse()
        raw = response.read()
    except OSError as exc:
        pytest.fail(f"Failed to connect to the server at http://{URL_HOST}:{URL_PORT}/compute: {exc}")
    finally:
        conn.close()

    assert response.status == 200, f"Expected HTTP 200, got {response.status}"
    try:
        decoded = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        pytest.fail(f"Response is not valid JSON: {raw!r}: {exc}")

    assert isinstance(decoded, dict), "Response JSON must be an object"
    assert "checksum" in decoded, "Response JSON missing 'checksum' key"
    assert "compatible" in decoded, "Response JSON missing 'compatible' key"
    assert set(decoded) == {"checksum", "compatible"}, "Response JSON contains unexpected keys"
    return decoded


def assert_compute(version, body, compatible):
    result = post_compute(version, body)
    expected_checksum = (SEED + sum(body)) & 0xFFFFFFFF
    assert result["checksum"] == expected_checksum, (
        f"Expected checksum {expected_checksum}, got {result['checksum']}"
    )
    assert result["compatible"] is compatible, (
        f"Expected compatible to be {compatible}, got {result['compatible']}"
    )


def test_shared_library_compiled_and_implemented():
    """Verify the artifact exists, loads, exports both functions, and computes correctly."""
    assert os.path.isfile(SO_PATH), (
        f"Shared library missing at {SO_PATH}. Did the Makefile run successfully?"
    )
    load_and_check_library(SO_PATH)


def test_makefile_rebuilds_library_from_assembly():
    """Exercise the submitted Makefile in isolation and verify asm_checksum comes from the NASM object."""
    with tempfile.TemporaryDirectory() as build_dir:
        for name in ("Makefile", "libchecksum.c", "checksum_x86_64.s"):
            source = os.path.join(PROJECT, name)
            assert os.path.isfile(source), f"Missing required project file: {source}"
            shutil.copy2(source, os.path.join(build_dir, name))

        subprocess.run(
            ["make", "clean"], cwd=build_dir, check=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=15,
        )
        subprocess.run(
            ["make", "all"], cwd=build_dir, check=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=30,
        )

        rebuilt_so = os.path.join(build_dir, "libchecksum.so")
        rebuilt_obj = os.path.join(build_dir, "checksum_x86_64.o")
        assert os.path.isfile(rebuilt_so), "Makefile did not produce libchecksum.so"
        assert os.path.isfile(rebuilt_obj), "Makefile did not produce checksum_x86_64.o"

        nm = subprocess.run(
            ["nm", "-g", "--defined-only", rebuilt_obj], check=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=5,
        ).stdout
        assert any(line.split()[-1:] == ["asm_checksum"] for line in nm.splitlines()), (
            "checksum_x86_64.o does not define the global asm_checksum symbol"
        )
        load_and_check_library(rebuilt_so)


def test_http_server_compute_compatible():
    result = post_compute("2.5.0", b"hello")
    assert result["checksum"] == 1115, f"Expected checksum 1115, got {result['checksum']}"
    assert result["compatible"] is True, f"Expected compatible to be True, got {result['compatible']}"


def test_http_server_compute_incompatible_major():
    result = post_compute("3.0.0", b"test")
    assert result["checksum"] == 1031, f"Expected checksum 1031, got {result['checksum']}"
    assert result["compatible"] is False, f"Expected compatible to be False, got {result['compatible']}"


def test_http_server_compute_incompatible_minor():
    result = post_compute("2.0.9", b"foo")
    assert result["checksum"] == 907, f"Expected checksum 907, got {result['checksum']}"
    assert result["compatible"] is False, f"Expected compatible to be False, got {result['compatible']}"


def test_http_server_compute_exact_version():
    result = post_compute("2.1.0", b"A")
    assert result["checksum"] == 648, f"Expected checksum 648, got {result['checksum']}"
    assert result["compatible"] is True, f"Expected compatible to be True, got {result['compatible']}"


def test_http_server_randomized_behavior():
    """Use unpredictable bodies and versions so fixed canned responses cannot pass."""
    rng = random.SystemRandom()
    cases = [
        ("2.1.0", os.urandom(rng.randrange(0, 4097)), True),
        (f"2.1.{rng.randrange(1, 10000)}", os.urandom(rng.randrange(0, 4097)), True),
        (f"2.{rng.randrange(2, 100)}.{rng.randrange(0, 10000)}", os.urandom(rng.randrange(0, 4097)), True),
        (f"2.0.{rng.randrange(0, 10000)}", os.urandom(rng.randrange(0, 4097)), False),
    ]
    for _ in range(12):
        major = rng.choice([0, 1, 3, 4, 7, 11])
        cases.append((
            f"{major}.{rng.randrange(0, 100)}.{rng.randrange(0, 10000)}",
            os.urandom(rng.randrange(0, 4097)),
            False,
        ))
    rng.shuffle(cases)
    for version, body, compatible in cases:
        assert_compute(version, body, compatible)


def listener_pids():
    inodes = set()
    with open("/proc/net/tcp", "r", encoding="ascii") as tcp:
        next(tcp)
        for line in tcp:
            fields = line.split()
            if len(fields) > 9 and fields[1] == "0100007F:1F90" and fields[3] == "0A":
                inodes.add(fields[9])

    owners = set()
    for pid in (p for p in os.listdir("/proc") if p.isdigit()):
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    owners.add(int(pid))
        except OSError:
            continue
    return owners


def mapped_library_pids():
    owners = set()
    target = os.path.realpath(SO_PATH)
    for pid in (p for p in os.listdir("/proc") if p.isdigit()):
        try:
            with open(f"/proc/{pid}/maps", "r", encoding="utf-8", errors="replace") as maps:
                for line in maps:
                    fields = line.rstrip("\n").split(maxsplit=5)
                    if len(fields) == 6 and fields[5] == target:
                        owners.add(int(pid))
                        break
        except OSError:
            continue
    return owners


def ancestors(pid):
    result = {pid}
    while pid > 1:
        try:
            with open(f"/proc/{pid}/status", "r", encoding="ascii") as status:
                ppid = next(
                    int(line.split()[1]) for line in status if line.startswith("PPid:")
                )
        except (OSError, StopIteration, ValueError):
            break
        if ppid in result:
            break
        result.add(ppid)
        pid = ppid
    return result


def test_listening_service_has_loaded_submitted_library():
    listeners = listener_pids()
    assert listeners, "No process is listening exactly on 127.0.0.1:8080"
    mappers = mapped_library_pids()
    assert mappers, f"No running process has loaded {SO_PATH}"

    related = False
    for listener in listeners:
        listener_family = ancestors(listener)
        for mapper in mappers:
            mapper_family = ancestors(mapper)
            if listener in mapper_family or mapper in listener_family:
                related = True
                break
    assert related, "The service listening on port 8080 is not associated with a process that loaded libchecksum.so"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
