#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import importlib.machinery
import os
import secrets
import signal
import subprocess
import sys
import time
from pathlib import Path

import pytest


def fnv1a_hash(data: bytes) -> int:
    """Compute the FNV-1a hash exactly as the C extension should."""
    h = 14695981039346656037
    for b in data:
        h ^= b
        h *= 1099511628211
        h &= 0xFFFFFFFFFFFFFFFF
    return h


def test_c_extension_fixed():
    """Verify that the deliberate crash was removed from fasthash.c."""
    c_file = "/app/vendored/pyfasthash/fasthash.c"
    assert os.path.exists(c_file), f"{c_file} is missing."
    with open(c_file, "r") as f:
        content = f.read()
    assert '__asm__("ud2");' not in content, (
        'fasthash.c still contains the deliberate crash instruction '
        "'__asm__(\"ud2\");'."
    )


def test_setup_py_fixed():
    """Verify that the invalid compiler flag was removed from setup.py."""
    setup_file = "/app/vendored/pyfasthash/setup.py"
    assert os.path.exists(setup_file), f"{setup_file} is missing."
    with open(setup_file, "r") as f:
        content = f.read()
    assert "-Werror=invalid-flag-that-breaks-build" not in content, (
        "setup.py still contains the invalid compiler flag."
    )


def test_installed_native_extension():
    """Import and exercise the installed native extension on undisclosed inputs."""
    try:
        import pyfasthash_c
        import pyfasthash
    except Exception as exc:
        pytest.fail(f"The installed pyfasthash package could not be imported: {exc}")

    extension_path = getattr(pyfasthash_c, "__file__", "") or ""
    assert any(extension_path.endswith(s) for s in importlib.machinery.EXTENSION_SUFFIXES), (
        f"pyfasthash_c is not an installed native extension: {extension_path!r}"
    )
    assert callable(getattr(pyfasthash_c, "compute_fast_hash", None)), (
        "pyfasthash_c.compute_fast_hash is missing or not callable"
    )

    samples = [b"", b"hello world", b"embedded\x00nul", bytes(range(256))]
    samples.extend(secrets.token_bytes(secrets.randbelow(512)) for _ in range(12))
    for data in samples:
        actual = pyfasthash_c.compute_fast_hash(data)
        assert actual == fnv1a_hash(data), (
            f"compute_fast_hash returned {actual} instead of the expected hash "
            f"for a {len(data)}-byte input"
        )

    text = "installed-wrapper-" + secrets.token_hex(18) + "-λ雪"
    assert pyfasthash.hash_string(text) == fnv1a_hash(text.encode("utf-8"))


def load_grpc_modules():
    sys.path.insert(0, "/home/user")
    try:
        import grpc
        import service_pb2
        import service_pb2_grpc
    except ImportError as exc:
        pytest.fail(
            "Failed to import grpc or the compiled protobuf files from /home/user: "
            f"{exc}"
        )
    return grpc, service_pb2, service_pb2_grpc


def rpc_hash(stub, service_pb2, grpc, items):
    request = service_pb2.HashRequest(items=items)
    try:
        return stub.ComputeHash(request, timeout=3).hash_value
    except grpc.RpcError as exc:
        pytest.fail(f"gRPC ComputeHash call failed for {items}: {exc}")


def test_grpc_service():
    """Exercise the running service on fixed and verifier-generated inputs."""
    assert os.path.isfile("/home/user/server.py"), "/home/user/server.py is missing"
    assert os.path.isfile("/home/user/service.proto"), "/home/user/service.proto is missing"

    grpc, service_pb2, service_pb2_grpc = load_grpc_modules()
    channel = grpc.insecure_channel("127.0.0.1:50051")
    try:
        grpc.channel_ready_future(channel).result(timeout=3)
        stub = service_pb2_grpc.HashServiceStub(channel)

        # Preserve the original disclosed cases.
        cases = [
            ["hello", "world"],
            ["fast", "hash", "grpc", "test"],
        ]

        alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-λ雪🙂"
        for _ in range(10):
            parts = []
            for _ in range(secrets.randbelow(8)):
                parts.append(
                    "".join(secrets.choice(alphabet) for _ in range(secrets.randbelow(45)))
                )
            cases.append(parts)

        for items in cases:
            expected = fnv1a_hash("".join(items).encode("utf-8"))
            actual = rpc_hash(stub, service_pb2, grpc, items)
            assert actual == expected, (
                f"For items {items}, expected hash {expected}, but got {actual}."
            )
    finally:
        channel.close()


def listener_pids(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
                inodes.add(fields[9])

    pids = set()
    for proc in Path("/proc").glob("[0-9]*"):
        try:
            for fd in (proc / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(proc.name))
                    break
        except OSError:
            continue
    return pids


def stop_port(port):
    pids = listener_pids(port)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and listener_pids(port):
        time.sleep(0.05)
    for pid in listener_pids(port):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listener_pids(port):
        time.sleep(0.05)


def start_real_server(grpc):
    proc = subprocess.Popen(
        [sys.executable, "/home/user/server.py"],
        cwd="/home/user",
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    channel = grpc.insecure_channel("127.0.0.1:50051")
    try:
        grpc.channel_ready_future(channel).result(timeout=6)
    except Exception:
        proc.poll()
        raise
    finally:
        channel.close()
    return proc


def test_server_actually_calls_c_extension(tmp_path):
    """Run server.py against an instrumented extension to prove the RPC calls it."""
    grpc, service_pb2, service_pb2_grpc = load_grpc_modules()
    secret = secrets.token_hex(32)
    call_log = tmp_path / "extension_calls.log"
    fake_dir = tmp_path / "instrumented"
    fake_dir.mkdir()
    (fake_dir / "pyfasthash_c.py").write_text(
        "import base64, hashlib, os\n"
        "def compute_fast_hash(data):\n"
        "    if not isinstance(data, bytes):\n"
        "        raise TypeError('compute_fast_hash must receive bytes')\n"
        "    with open(os.environ['FASTHASH_CALL_LOG'], 'ab') as f:\n"
        "        f.write(base64.b64encode(data) + b'\\n')\n"
        "    return int.from_bytes(hashlib.blake2b(data, key=os.environ['FASTHASH_TEST_KEY'].encode(), digest_size=8).digest(), 'big')\n"
    )

    env = os.environ.copy()
    env["FASTHASH_TEST_KEY"] = secret
    env["FASTHASH_CALL_LOG"] = str(call_log)
    env["PYTHONPATH"] = str(fake_dir) + os.pathsep + "/home/user" + os.pathsep + env.get("PYTHONPATH", "")

    instrumented = None
    try:
        stop_port(50051)
        instrumented = subprocess.Popen(
            [sys.executable, "/home/user/server.py"],
            cwd="/home/user",
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )

        channel = grpc.insecure_channel("127.0.0.1:50051")
        try:
            grpc.channel_ready_future(channel).result(timeout=6)
            stub = service_pb2_grpc.HashServiceStub(channel)
            cases = [
                [],
                [secrets.token_hex(13)],
                ["left-" + secrets.token_hex(8), "-λ雪-", secrets.token_hex(11)],
            ]
            expected_calls = []
            for items in cases:
                data = "".join(items).encode("utf-8")
                expected_calls.append(base64.b64encode(data))
                expected = int.from_bytes(
                    hashlib.blake2b(data, key=secret.encode(), digest_size=8).digest(),
                    "big",
                )
                actual = rpc_hash(stub, service_pb2, grpc, items)
                assert actual == expected, (
                    "server.py did not return the result supplied by "
                    "pyfasthash_c.compute_fast_hash"
                )
        finally:
            channel.close()

        logged = call_log.read_bytes().splitlines() if call_log.exists() else []
        for encoded in expected_calls:
            assert encoded in logged, (
                "server.py did not pass the concatenated request bytes to "
                "pyfasthash_c.compute_fast_hash"
            )
    finally:
        stop_port(50051)
        if instrumented is not None and instrumented.poll() is None:
            instrumented.kill()
            instrumented.wait(timeout=2)
        # Restore the submitted real server so it remains listening after verification.
        start_real_server(grpc)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
