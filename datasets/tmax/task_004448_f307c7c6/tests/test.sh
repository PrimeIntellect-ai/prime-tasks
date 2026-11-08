#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import re
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time
from concurrent import futures

import grpc
from grpc_tools import protoc

SO_PATH = "/home/user/rust_lib/target/release/librust_lib.so"
SCRIPT_PATH = "/home/user/run_client.sh"
PROTO_PATH = "/home/user/grpc/service.proto"
SERVER_PATH = "/home/user/grpc/server.py"


def listener_pids(port=50051):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    cols = line.split()
                    if len(cols) > 9 and cols[1].rsplit(":", 1)[-1].upper() == wanted and cols[3] == "0A":
                        inodes.add(cols[9])
        except FileNotFoundError:
            pass

    pids = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(name))
                    break
        except OSError:
            pass
    return pids


def kill_port():
    for pid in listener_pids():
        if pid != os.getpid():
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
    time.sleep(0.4)
    for pid in listener_pids():
        if pid != os.getpid():
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
    time.sleep(0.2)


def start_server():
    kill_port()
    proc = subprocess.Popen(
        [sys.executable, SERVER_PATH],
        cwd="/home/user/grpc",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    channel = grpc.insecure_channel("localhost:50051")
    try:
        grpc.channel_ready_future(channel).result(timeout=8)
    except Exception:
        proc.poll()
        raise AssertionError("server.py did not start a gRPC listener on localhost:50051")
    finally:
        channel.close()
    return proc


def stop_server(proc):
    if proc is not None and proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
    kill_port()


def run_client(payload):
    with tempfile.NamedTemporaryFile(delete=False) as tmp:
        tmp.write(payload)
        path = tmp.name
    try:
        return subprocess.run([SCRIPT_PATH, path], capture_output=True, text=True, timeout=10)
    finally:
        os.remove(path)


def mapped_checksum_library(pids):
    candidates = set()
    for pid in pids:
        try:
            with open(f"/proc/{pid}/maps") as f:
                for line in f:
                    parts = line.rstrip().split(None, 5)
                    if len(parts) == 6 and parts[5].startswith("/"):
                        path = parts[5].removesuffix(" (deleted)")
                        if os.path.isfile(path) and path.endswith(".so"):
                            candidates.add(path)
        except OSError:
            pass
    for path in candidates:
        result = subprocess.run(["nm", "-D", path], capture_output=True, text=True)
        if result.returncode == 0 and re.search(r"\bcompute_checksum$", result.stdout, re.MULTILINE):
            return path
    return None


def test_rust_library_built():
    assert os.path.isfile(SO_PATH), f"Rust shared library not found at {SO_PATH}"


def test_bash_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Bash script not found at {SCRIPT_PATH}"
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Bash script at {SCRIPT_PATH} is not executable"


def test_complete_grpc_rust_integration():
    assert os.path.isfile(PROTO_PATH), f"Protocol Buffers file not found at {PROTO_PATH}"
    assert os.path.isfile(SERVER_PATH), f"Python gRPC server not found at {SERVER_PATH}"

    rust_source = open("/home/user/rust_lib/src/lib.rs").read()
    assert re.search(r"#\s*\[\s*no_mangle\s*\]", rust_source), "compute_checksum is not marked #[no_mangle]"
    assert re.search(r'extern\s+"C"\s+fn\s+compute_checksum\s*\(', rust_source), "compute_checksum is not exported with the C ABI"
    assert re.search(r"\*const\s+u8", rust_source), "compute_checksum does not take a raw byte pointer"
    assert re.search(r"\busize\b", rust_source) and re.search(r"->\s*u16", rust_source), "compute_checksum has the wrong length or return type"

    subprocess.run(["cargo", "build", "--release"], cwd="/home/user/rust_lib", check=True, timeout=120)
    assert os.path.isfile(SO_PATH), f"Rust shared library not found at {SO_PATH}"
    symbols = subprocess.run(["nm", "-D", SO_PATH], capture_output=True, text=True, check=True).stdout
    assert re.search(r"\bcompute_checksum$", symbols, re.MULTILINE), "shared library does not export compute_checksum"

    lib = ctypes.CDLL(SO_PATH)
    fn = lib.compute_checksum
    fn.argtypes = [ctypes.POINTER(ctypes.c_uint8), ctypes.c_size_t]
    fn.restype = ctypes.c_uint16
    for payload in (b"hello world", os.urandom(4096)):
        buf = (ctypes.c_uint8 * len(payload)).from_buffer_copy(payload)
        assert fn(buf, len(payload)) == sum(payload) % 65536, "Rust compute_checksum returned an incorrect result"

    server_source = open(SERVER_PATH).read()
    assert "ctypes" in server_source and "CDLL" in server_source, "server.py does not load the Rust library with ctypes"
    assert "compute_checksum" in server_source, "server.py does not invoke compute_checksum"
    assert "50051" in server_source, "server.py is not configured for port 50051"

    with tempfile.TemporaryDirectory() as generated:
        rc = protoc.main([
            "grpc_tools.protoc",
            f"-I{os.path.dirname(PROTO_PATH)}",
            f"--python_out={generated}",
            f"--grpc_python_out={generated}",
            PROTO_PATH,
        ])
        assert rc == 0, "service.proto could not be compiled"
        sys.path.insert(0, generated)
        try:
            import service_pb2
            import service_pb2_grpc

            desc = service_pb2.DESCRIPTOR
            assert desc.package == "checksum"
            req = desc.message_types_by_name.get("PayloadRequest")
            resp = desc.message_types_by_name.get("ChecksumResponse")
            svc = desc.services_by_name.get("ChecksumService")
            assert req is not None and len(req.fields) == 1
            assert req.fields[0].name == "data" and req.fields[0].number == 1 and req.fields[0].type == req.fields[0].TYPE_BYTES
            assert resp is not None and len(resp.fields) == 1
            assert resp.fields[0].name == "checksum" and resp.fields[0].number == 1 and resp.fields[0].type == resp.fields[0].TYPE_UINT32
            assert svc is not None and len(svc.methods) == 1 and svc.methods[0].name == "Calculate"
            assert svc.methods[0].input_type.full_name == "checksum.PayloadRequest"
            assert svc.methods[0].output_type.full_name == "checksum.ChecksumResponse"

            # Start the submitted server and call it directly over gRPC.
            proc = start_server()
            try:
                channel = grpc.insecure_channel("localhost:50051")
                stub = service_pb2_grpc.ChecksumServiceStub(channel)
                payload = os.urandom(1537)
                response = stub.Calculate(service_pb2.PayloadRequest(data=payload), timeout=5)
                assert response.checksum == sum(payload) % 65536
                rust_path = mapped_checksum_library(listener_pids())
                assert rust_path is not None, "running server has not loaded a shared library exporting compute_checksum"
                channel.close()
            finally:
                stop_server(proc)

            # Replace the exact Rust library loaded by the server with a probe ABI.
            # A Python-only checksum implementation cannot pass these requests.
            backup = rust_path + ".verifier-backup"
            if os.path.exists(backup):
                os.remove(backup)
            os.replace(rust_path, backup)
            probe_c = rust_path + ".probe.c"
            try:
                with open(probe_c, "w") as f:
                    f.write("#include <stdint.h>\n#include <stddef.h>\nuint16_t compute_checksum(const uint8_t *p, size_t n) { uint32_t s=0; for(size_t i=0;i<n;i++) s+=p[i]; return (uint16_t)((s*7u+1234u)&65535u); }\n")
                subprocess.run(["gcc", "-shared", "-fPIC", "-O2", "-o", rust_path, probe_c], check=True)
                proc = start_server()
                try:
                    channel = grpc.insecure_channel("localhost:50051")
                    stub = service_pb2_grpc.ChecksumServiceStub(channel)
                    for payload in (b"grpc-rust-probe", os.urandom(321)):
                        got = stub.Calculate(service_pb2.PayloadRequest(data=payload), timeout=5).checksum
                        expected = (sum(payload) * 7 + 1234) & 65535
                        assert got == expected, "server does not pass gRPC payload bytes to the Rust compute_checksum ABI"
                    channel.close()
                finally:
                    stop_server(proc)
            finally:
                if os.path.exists(rust_path):
                    os.remove(rust_path)
                os.replace(backup, rust_path)
                if os.path.exists(probe_c):
                    os.remove(probe_c)

            # Preserve the original fixed and random end-to-end client assertions.
            proc = start_server()
            try:
                for payload in (b"hello world", os.urandom(1024)):
                    expected_checksum = sum(payload) % 65536
                    result = run_client(payload)
                    assert result.returncode == 0, f"Client script failed with return code {result.returncode}. Stderr: {result.stderr}"
                    output = result.stdout.strip()
                    assert output == str(expected_checksum), f"Expected checksum {expected_checksum}, but got {output}"
            finally:
                stop_server(proc)

            # Serve deliberately non-checksum values and verify the client sends the
            # file bytes over gRPC and prints the RPC response rather than computing locally.
            seen = []
            class MockServicer(service_pb2_grpc.ChecksumServiceServicer):
                def Calculate(self, request, context):
                    seen.append(bytes(request.data))
                    return service_pb2.ChecksumResponse(checksum=60000 + len(request.data) % 1000)

            mock = grpc.server(futures.ThreadPoolExecutor(max_workers=2))
            service_pb2_grpc.add_ChecksumServiceServicer_to_server(MockServicer(), mock)
            assert mock.add_insecure_port("localhost:50051") != 0
            mock.start()
            try:
                payload = os.urandom(287)
                result = run_client(payload)
                assert result.returncode == 0, f"Client failed against the gRPC service: {result.stderr}"
                assert result.stdout.strip() == str(60000 + len(payload) % 1000), "client does not print the gRPC response"
                assert seen == [payload], "client did not send the input file contents as the gRPC data payload"
            finally:
                mock.stop(0).wait()
                kill_port()

            no_arg = subprocess.run([SCRIPT_PATH], capture_output=True, text=True, timeout=5)
            two_args = subprocess.run([SCRIPT_PATH, "/dev/null", "/dev/null"], capture_output=True, text=True, timeout=5)
            assert no_arg.returncode != 0 and two_args.returncode != 0, "run_client.sh must accept exactly one argument"

            # Leave the genuine submitted server running, as required, and verify it once more.
            final_proc = start_server()
            payload = os.urandom(513)
            result = run_client(payload)
            assert result.returncode == 0 and result.stdout.strip() == str(sum(payload) % 65536)
            assert final_proc.poll() is None, "gRPC server is not left running"
        finally:
            sys.path.remove(generated)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
