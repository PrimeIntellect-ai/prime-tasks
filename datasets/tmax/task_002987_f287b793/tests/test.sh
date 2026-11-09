#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import collections
import hashlib
import hmac
import json
import os
import secrets
import subprocess
import sys
import tempfile
import threading
import time
from concurrent import futures

import grpc

PROTO = "/home/user/rust_auth/proto/auth.proto"


def compile_proto(tmpdir):
    subprocess.run([
        sys.executable, "-m", "grpc_tools.protoc",
        f"-I{os.path.dirname(PROTO)}",
        f"--python_out={tmpdir}",
        f"--grpc_python_out={tmpdir}",
        PROTO,
    ], check=True)


def expected_token(user_id, payload):
    message = f"{user_id}|{payload}".encode("utf-8")
    return hmac.new(b"WINTERMUTE_2049", message, hashlib.sha256).hexdigest()


def test_files_and_compiled_stubs_exist():
    assert os.path.isfile("/home/user/server.py"), "/home/user/server.py is missing"
    assert os.path.isfile("/home/user/test_auth.py"), "/home/user/test_auth.py is missing"

    stub_files = []
    for root, _, files in os.walk("/home/user"):
        for name in files:
            if name in {"auth_pb2.py", "auth_pb2_grpc.py"}:
                stub_files.append(os.path.join(root, name))
    names = {os.path.basename(path) for path in stub_files}
    assert "auth_pb2.py" in names, "compiled auth_pb2.py is missing"
    assert "auth_pb2_grpc.py" in names, "compiled auth_pb2_grpc.py is missing"
    for path in stub_files:
        subprocess.run([sys.executable, "-m", "py_compile", path], check=True)


def test_server_general_algorithm():
    with tempfile.TemporaryDirectory() as tmpdir:
        compile_proto(tmpdir)
        sys.path.insert(0, tmpdir)
        try:
            import auth_pb2
            import auth_pb2_grpc

            proc = subprocess.Popen([sys.executable, "/home/user/server.py"])
            channel = grpc.insecure_channel("127.0.0.1:50051")
            try:
                grpc.channel_ready_future(channel).result(timeout=8)
                stub = auth_pb2_grpc.AuthServiceStub(channel)

                cases = [
                    ("", ""),
                    ("user|with|pipes", "payload|with|pipes"),
                    ("雪だるま", "данные-🔐"),
                    ("a", "x" * 2048),
                ]
                for i in range(100):
                    user_id = f"u-{i}-{secrets.token_urlsafe(12)}"
                    payload = f"p|{secrets.token_urlsafe(8)}|{secrets.token_hex((i % 24) + 1)}"
                    cases.append((user_id, payload))

                for user_id, payload in cases:
                    response = stub.GenerateToken(
                        auth_pb2.GenerateTokenRequest(user_id=user_id, payload=payload),
                        timeout=5,
                    )
                    assert response.token == expected_token(user_id, payload)
            finally:
                channel.close()
                proc.terminate()
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait()
        finally:
            sys.path.pop(0)
            sys.modules.pop("auth_pb2_grpc", None)
            sys.modules.pop("auth_pb2", None)


def _load_generated_modules(tmpdir):
    compile_proto(tmpdir)
    sys.path.insert(0, tmpdir)
    import auth_pb2
    import auth_pb2_grpc
    return auth_pb2, auth_pb2_grpc


def _run_controlled_services(auth_pb2, auth_pb2_grpc, log_path, mismatch=False):
    lock = threading.Lock()

    class ControlledAuth(auth_pb2_grpc.AuthServiceServicer):
        def __init__(self, side):
            self.side = side

        def GenerateToken(self, request, context):
            with lock:
                with open(log_path, "a", encoding="utf-8") as handle:
                    handle.write(json.dumps([self.side, request.user_id, request.payload]) + "\n")
            token = expected_token(request.user_id, request.payload)
            if mismatch and self.side == "python":
                token = "0" * 64
            return auth_pb2.GenerateTokenResponse(token=token)

    servers = []
    for side, port in (("legacy", 50050), ("python", 50051)):
        server = grpc.server(futures.ThreadPoolExecutor(max_workers=12))
        auth_pb2_grpc.add_AuthServiceServicer_to_server(ControlledAuth(side), server)
        assert server.add_insecure_port(f"127.0.0.1:{port}") == port
        server.start()
        servers.append(server)
    return servers


def _stop_servers(servers):
    for server in servers:
        server.stop(0).wait()


def _read_calls(path):
    calls = {"legacy": [], "python": []}
    if not os.path.exists(path):
        return calls
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            side, user_id, payload = json.loads(line)
            calls[side].append((user_id, payload))
    return calls


def _run_user_pytest(extra_env=None):
    env = os.environ.copy()
    if extra_env:
        env.update(extra_env)
    return subprocess.run(
        [sys.executable, "-m", "pytest", "-q", "/home/user/test_auth.py"],
        capture_output=True,
        text=True,
        timeout=90,
        env=env,
    )


def test_user_suite_really_exercises_oracle_and_profiles_memory():
    source = open("/home/user/test_auth.py", encoding="utf-8").read()
    tree = ast.parse(source)
    imported_roots = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imported_roots.update(alias.name.split(".")[0] for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            imported_roots.add(node.module.split(".")[0])
    assert "tracemalloc" in imported_roots, "test_auth.py must use tracemalloc"
    assert imported_roots.intersection({"random", "secrets", "uuid"}), \
        "test_auth.py must generate randomized requests"

    with tempfile.TemporaryDirectory() as tmpdir:
        auth_pb2, auth_pb2_grpc = _load_generated_modules(tmpdir)
        try:
            good_log = os.path.join(tmpdir, "good.jsonl")
            servers = _run_controlled_services(auth_pb2, auth_pb2_grpc, good_log)
            try:
                result = _run_user_pytest()
            finally:
                _stop_servers(servers)
            assert result.returncode == 0, \
                f"test_auth.py failed against matching services:\n{result.stdout}\n{result.stderr}"

            calls = _read_calls(good_log)
            legacy = collections.Counter(calls["legacy"])
            python = collections.Counter(calls["python"])
            assert len(calls["legacy"]) >= 100, "test_auth.py sent fewer than 100 oracle requests"
            assert len(calls["python"]) >= 100, "test_auth.py sent fewer than 100 Python-server requests"
            assert len(legacy) >= 90 and len(python) >= 90, "requests are not sufficiently varied"
            assert legacy == python, "the exact same requests were not sent to both services"

            bad_log = os.path.join(tmpdir, "bad.jsonl")
            servers = _run_controlled_services(auth_pb2, auth_pb2_grpc, bad_log, mismatch=True)
            try:
                result = _run_user_pytest()
            finally:
                _stop_servers(servers)
            assert result.returncode != 0, \
                "test_auth.py passed even when every Python token differed from the oracle"

            patch_dir = os.path.join(tmpdir, "patch")
            os.mkdir(patch_dir)
            with open(os.path.join(patch_dir, "sitecustomize.py"), "w", encoding="utf-8") as handle:
                handle.write(
                    "import tracemalloc\n"
                    "_real = tracemalloc.get_traced_memory\n"
                    "def _forced_high_peak():\n"
                    "    current, peak = _real()\n"
                    "    return current, max(peak, 6 * 1024 * 1024)\n"
                    "tracemalloc.get_traced_memory = _forced_high_peak\n"
                )
            memory_log = os.path.join(tmpdir, "memory.jsonl")
            servers = _run_controlled_services(auth_pb2, auth_pb2_grpc, memory_log)
            try:
                old_pythonpath = os.environ.get("PYTHONPATH", "")
                pythonpath = patch_dir + (os.pathsep + old_pythonpath if old_pythonpath else "")
                result = _run_user_pytest({"PYTHONPATH": pythonpath})
            finally:
                _stop_servers(servers)
            assert result.returncode != 0, \
                "test_auth.py did not reject a tracemalloc peak above 5MB"
        finally:
            sys.path.pop(0)
            sys.modules.pop("auth_pb2_grpc", None)
            sys.modules.pop("auth_pb2", None)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
