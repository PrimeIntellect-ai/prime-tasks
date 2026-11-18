#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import math
import os
import random
import shutil
import signal
import subprocess
import sys
import time
from concurrent import futures

import grpc
import pytest

BASE_DIR = "/home/user/release_prep"


def test_libbilling_so_exists():
    filepath = os.path.join(BASE_DIR, "libbilling.so")
    assert os.path.isfile(filepath), f"Shared library {filepath} does not exist. Did you compile the C code?"


def test_billing_core_patched():
    filepath = os.path.join(BASE_DIR, "billing_core.c")
    assert os.path.isfile(filepath), f"File {filepath} is missing."
    with open(filepath, "r") as f:
        content = f.read()
    assert "current * 0.90" in content, f"The file {filepath} does not appear to be patched correctly."
    assert "current * 1.10" not in content, f"The file {filepath} still contains the bug."


def test_grpc_bindings_generated():
    pb2_file = os.path.join(BASE_DIR, "billing_pb2.py")
    pb2_grpc_file = os.path.join(BASE_DIR, "billing_pb2_grpc.py")
    assert os.path.isfile(pb2_file), f"gRPC binding file {pb2_file} is missing. Did you generate the bindings?"
    assert os.path.isfile(pb2_grpc_file), f"gRPC binding file {pb2_grpc_file} is missing. Did you generate the bindings?"


def test_server_py_exists():
    filepath = os.path.join(BASE_DIR, "server.py")
    assert os.path.isfile(filepath), f"Server script {filepath} does not exist."


def test_verify_release_py_exists():
    filepath = os.path.join(BASE_DIR, "verify_release.py")
    assert os.path.isfile(filepath), f"Verification script {filepath} does not exist."


def test_deployment_verification_log():
    filepath = os.path.join(BASE_DIR, "deployment_verification.log")
    assert os.path.isfile(filepath), f"Log file {filepath} does not exist. Did you run the verification script?"
    with open(filepath, "r") as f:
        content = f.read().strip()
    expected_total = 100.0 + (200.0 * 0.90) + 300.0
    expected_string = f"FINAL_TOTAL: {expected_total}"
    assert expected_string in content, f"Log file {filepath} does not contain the expected text '{expected_string}'. Found: '{content}'"


def _kill_port_50051_listeners():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].rsplit(":", 1)[-1].upper() == format(50051, "04X"):
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass
    for pid in os.listdir("/proc"):
        if not pid.isdigit() or int(pid) == os.getpid():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    try:
                        os.kill(int(pid), signal.SIGTERM)
                    except (ProcessLookupError, PermissionError):
                        pass
                    break
        except (FileNotFoundError, PermissionError):
            pass
    time.sleep(0.4)


def _start_submission_server(pb2_grpc):
    _kill_port_50051_listeners()
    proc = subprocess.Popen(
        [sys.executable, os.path.join(BASE_DIR, "server.py")],
        cwd=BASE_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    channel = grpc.insecure_channel("localhost:50051")
    deadline = time.time() + 10
    while time.time() < deadline:
        if proc.poll() is not None:
            out, err = proc.communicate(timeout=1)
            pytest.fail(f"server.py exited before serving requests (code {proc.returncode}). stdout={out!r}, stderr={err!r}")
        try:
            grpc.channel_ready_future(channel).result(timeout=0.25)
            return proc, channel, pb2_grpc.BillingServiceStub(channel)
        except grpc.FutureTimeoutError:
            pass
    _stop_submission_server(proc, channel)
    pytest.fail("server.py did not start a gRPC server on localhost:50051")


def _stop_submission_server(proc, channel):
    try:
        channel.close()
    except Exception:
        pass
    if proc.poll() is None:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
            proc.wait(timeout=3)
        except (ProcessLookupError, subprocess.TimeoutExpired):
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
    _kill_port_50051_listeners()


def _expected_discount(items):
    return sum(amount * (0.90 if item_id % 2 == 0 else 1.0) for item_id, amount in items)


def test_real_library_bindings_server_and_verification_client():
    sys.path.insert(0, BASE_DIR)
    import billing_pb2
    import billing_pb2_grpc

    # Load and call the submitted shared object directly, proving it is a real
    # library with the required exported ABI and patched behavior.
    class LineItem(ctypes.Structure):
        _fields_ = [("item_id", ctypes.c_int), ("amount", ctypes.c_double)]

    lib_path = os.path.join(BASE_DIR, "libbilling.so")
    try:
        lib = ctypes.CDLL(lib_path)
        calculate_total = lib.calculate_total
    except (OSError, AttributeError) as exc:
        pytest.fail(f"libbilling.so is not a loadable library exporting calculate_total: {exc}")
    calculate_total.argtypes = [ctypes.POINTER(LineItem), ctypes.c_int]
    calculate_total.restype = ctypes.c_double

    rng = random.SystemRandom()
    direct_items = [(rng.randrange(11, 100), rng.uniform(1.25, 400.0)) for _ in range(7)]
    direct_items[0] = (direct_items[0][0] | 1, direct_items[0][1])
    direct_items[1] = (direct_items[1][0] & ~1, direct_items[1][1])
    array = (LineItem * len(direct_items))(*(LineItem(i, a) for i, a in direct_items))
    result = calculate_total(array, len(direct_items))
    assert result == pytest.approx(_expected_discount(direct_items), rel=1e-12, abs=1e-9)

    # Exercise the generated bindings and the submitted server against the real
    # patched library on values not present in the release checklist.
    proc, channel, stub = _start_submission_server(billing_pb2_grpc)
    try:
        for count in (1, 4, 9):
            items = [(rng.randrange(100, 10000), rng.uniform(0.5, 900.0)) for _ in range(count)]
            request = billing_pb2.CalculateRequest(
                items=[billing_pb2.LineItemMsg(item_id=i, amount=a) for i, a in items]
            )
            response = stub.Calculate(request, timeout=4)
            assert response.total == pytest.approx(_expected_discount(items), rel=1e-12, abs=1e-8)
    finally:
        _stop_submission_server(proc, channel)

    # Replace the library temporarily with a compatible probe implementation.
    # A genuine ctypes wrapper must now return the probe's deliberately different
    # calculation, while a hardcoded/Python-only server will fail.
    backup = lib_path + ".verifier_backup"
    probe_src = "/tmp/verifier_billing_probe.c"
    if os.path.exists(backup):
        os.unlink(backup)
    os.replace(lib_path, backup)
    try:
        with open(probe_src, "w") as f:
            f.write('''
struct LineItem { int item_id; double amount; };
double calculate_total(struct LineItem* items, int count) {
    double total = count * 0.125;
    for (int i = 0; i < count; ++i)
        total += items[i].amount * (items[i].item_id + 7);
    return total;
}
''')
        subprocess.run(["gcc", "-shared", "-fPIC", probe_src, "-o", lib_path], check=True, timeout=15)
        proc, channel, stub = _start_submission_server(billing_pb2_grpc)
        try:
            probe_items = [(2, 1.75), (9, 3.5), (14, 0.625), (21, 2.25)]
            request = billing_pb2.CalculateRequest(
                items=[billing_pb2.LineItemMsg(item_id=i, amount=a) for i, a in probe_items]
            )
            response = stub.Calculate(request, timeout=4)
            expected = len(probe_items) * 0.125 + sum(a * (i + 7) for i, a in probe_items)
            assert response.total == pytest.approx(expected, rel=1e-12, abs=1e-9), \
                "server.py did not pass the protobuf items through libbilling.so"
        finally:
            _stop_submission_server(proc, channel)
    finally:
        if os.path.exists(lib_path):
            os.unlink(lib_path)
        os.replace(backup, lib_path)

    # Run verify_release.py against a capturing gRPC service. This proves that it
    # sends the mandated request and writes the value returned by the RPC rather
    # than merely hardcoding the original expected log line.
    captured = []
    sentinel = 4321.125

    class CapturingService(billing_pb2_grpc.BillingServiceServicer):
        def Calculate(self, request, context):
            captured.append([(item.item_id, item.amount) for item in request.items])
            return billing_pb2.CalculateResponse(total=sentinel)

    _kill_port_50051_listeners()
    fake_server = grpc.server(futures.ThreadPoolExecutor(max_workers=2))
    billing_pb2_grpc.add_BillingServiceServicer_to_server(CapturingService(), fake_server)
    assert fake_server.add_insecure_port("localhost:50051") != 0
    log_path = os.path.join(BASE_DIR, "deployment_verification.log")
    with open(log_path, "r") as f:
        original_log = f.read()
    fake_server.start()
    try:
        completed = subprocess.run(
            [sys.executable, os.path.join(BASE_DIR, "verify_release.py")],
            cwd=BASE_DIR,
            capture_output=True,
            text=True,
            timeout=12,
        )
        assert completed.returncode == 0, f"verify_release.py failed: stdout={completed.stdout!r}, stderr={completed.stderr!r}"
        assert captured == [[(1, 100.0), (2, 200.0), (3, 300.0)]], \
            f"verify_release.py sent the wrong request: {captured!r}"
        with open(log_path, "r") as f:
            generated_log = f.read().strip()
        assert generated_log == f"FINAL_TOTAL: {sentinel}", \
            f"verify_release.py did not log the RPC response correctly: {generated_log!r}"
    finally:
        fake_server.stop(0).wait()
        with open(log_path, "w") as f:
            f.write(original_log)
        _kill_port_50051_listeners()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
