#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib
import math
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import uuid
from pathlib import Path

import grpc
import pytest
from google.protobuf import descriptor_pb2

HOME = Path("/home/user")


def test_results_log_exists():
    assert os.path.exists("/home/user/results.log"), "/home/user/results.log does not exist"


def test_results_log_content():
    expected_content = """1_linear.asm: 8.00
2_forward.asm: 13.00
3_loop.asm: 19.50"""

    with open("/home/user/results.log", "r") as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, f"Expected results.log to contain:\n{expected_content}\nBut got:\n{actual_content}"


def test_proto_file_exists():
    assert os.path.exists("/home/user/analyzer.proto"), "/home/user/analyzer.proto does not exist"


def test_server_file_exists():
    assert os.path.exists("/home/user/server.py"), "/home/user/server.py does not exist"


def test_client_file_exists():
    assert os.path.exists("/home/user/client.py"), "/home/user/client.py does not exist"


def test_generated_pb2_files_exist():
    assert os.path.exists("/home/user/analyzer_pb2.py"), "analyzer_pb2.py was not generated"
    assert os.path.exists("/home/user/analyzer_pb2_grpc.py"), "analyzer_pb2_grpc.py was not generated"


def test_artifacts_are_real_files():
    for name in ("analyzer.proto", "server.py", "client.py", "analyzer_pb2.py", "analyzer_pb2_grpc.py"):
        path = HOME / name
        assert path.is_file(), f"{path} is not a regular file"
        assert path.stat().st_size > 0, f"{path} is empty"


def test_proto_schema_is_correct(tmp_path):
    descriptor_path = tmp_path / "schema.pb"
    proc = subprocess.run(
        [
            sys.executable,
            "-m",
            "grpc_tools.protoc",
            "-I/home/user",
            f"--descriptor_set_out={descriptor_path}",
            "/home/user/analyzer.proto",
        ],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert proc.returncode == 0, f"analyzer.proto does not compile:\n{proc.stderr}"

    descriptor_set = descriptor_pb2.FileDescriptorSet()
    descriptor_set.ParseFromString(descriptor_path.read_bytes())
    assert len(descriptor_set.file) == 1
    fd = descriptor_set.file[0]
    assert fd.syntax == "proto3"
    assert fd.package == "asm_analyzer"

    messages = {m.name: m for m in fd.message_type}
    assert set(messages) == {"SnippetRequest", "SnippetResponse"}

    request = messages["SnippetRequest"]
    assert len(request.field) == 1
    assert request.field[0].name == "code"
    assert request.field[0].number == 1
    assert request.field[0].type == descriptor_pb2.FieldDescriptorProto.TYPE_STRING

    response = messages["SnippetResponse"]
    assert len(response.field) == 1
    assert response.field[0].name == "score"
    assert response.field[0].number == 1
    assert response.field[0].type == descriptor_pb2.FieldDescriptorProto.TYPE_FLOAT

    assert len(fd.service) == 1
    service = fd.service[0]
    assert service.name == "AssemblyAnalyzer"
    assert len(service.method) == 1
    method = service.method[0]
    assert method.name == "AnalyzeSnippet"
    assert method.input_type == ".asm_analyzer.SnippetRequest"
    assert method.output_type == ".asm_analyzer.SnippetResponse"


def _load_generated_modules():
    if str(HOME) not in sys.path:
        sys.path.insert(0, str(HOME))
    pb2 = importlib.import_module("analyzer_pb2")
    pb2_grpc = importlib.import_module("analyzer_pb2_grpc")
    assert hasattr(pb2, "SnippetRequest")
    assert hasattr(pb2, "SnippetResponse")
    assert hasattr(pb2_grpc, "AssemblyAnalyzerStub")
    assert hasattr(pb2_grpc, "AssemblyAnalyzerServicer")
    assert hasattr(pb2_grpc, "add_AssemblyAnalyzerServicer_to_server")
    return pb2, pb2_grpc


def test_generated_modules_are_importable():
    pb2, _ = _load_generated_modules()
    assert pb2.DESCRIPTOR.package == "asm_analyzer"
    assert pb2.SnippetRequest(code="mov eax, 1").code == "mov eax, 1"
    assert pb2.SnippetResponse(score=2.5).score == pytest.approx(2.5)


def _kill_existing_port_50051_listeners():
    inodes = set()
    target_port = 50051
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) < 10:
                continue
            try:
                port = int(fields[1].rsplit(":", 1)[1], 16)
            except (ValueError, IndexError):
                continue
            if port == target_port and fields[3] == "0A":
                inodes.add(fields[9])

    victims = set()
    for proc_dir in Path("/proc").glob("[0-9]*"):
        fd_dir = proc_dir / "fd"
        try:
            fds = list(fd_dir.iterdir())
        except OSError:
            continue
        for fd in fds:
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                victims.add(int(proc_dir.name))
                break

    for pid in victims:
        if pid != os.getpid():
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
    if victims:
        time.sleep(0.5)


@pytest.fixture(scope="session")
def running_service():
    _kill_existing_port_50051_listeners()
    proc = subprocess.Popen(
        [sys.executable, "/home/user/server.py"],
        cwd="/home/user",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        env={**os.environ, "PYTHONPATH": "/home/user"},
    )
    channel = grpc.insecure_channel("localhost:50051")
    try:
        grpc.channel_ready_future(channel).result(timeout=10)
        assert proc.poll() is None, "server.py exited instead of running continuously"
        pb2, pb2_grpc = _load_generated_modules()
        yield proc, channel, pb2, pb2_grpc
        assert proc.poll() is None, "server.py exited while servicing requests"
    except grpc.FutureTimeoutError:
        raise AssertionError(f"server.py did not start listening on port 50051 (exit={proc.poll()})")
    finally:
        channel.close()
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=5)


def _expected_score(code):
    costs = {
        "mov": 1, "push": 1, "pop": 1,
        "add": 2, "sub": 2, "inc": 2, "dec": 2, "cmp": 2,
        "jmp": 3, "je": 3, "jne": 3, "jz": 3, "jnz": 3,
        "mul": 4, "div": 4,
        "call": 5, "ret": 5,
    }
    jumps = {"jmp", "je", "jne", "jz", "jnz"}
    labels = {}
    base = 0
    backward = 0
    valid_order = 0

    for raw in code.splitlines():
        line = raw.strip()
        if not line or line.startswith(";"):
            continue
        if ";" in line:
            line = line.split(";", 1)[0].strip()
        if not line:
            continue
        valid_order += 1
        if line.endswith(":"):
            labels[line[:-1].strip()] = valid_order
            continue
        words = line.replace(",", " ").split()
        mnemonic = words[0].lower()
        operand = words[1] if len(words) > 1 else None
        base += costs.get(mnemonic, 0)
        if mnemonic in jumps and operand in labels and labels[operand] < valid_order:
            backward += 1
    return base * (1.5 ** backward)


def test_analyze_snippet_rpc_on_derived_cases(running_service):
    proc, channel, pb2, pb2_grpc = running_service
    stub = pb2_grpc.AssemblyAnalyzerStub(channel)
    cases = [
        "; ignored\nstart:\n MOV eax, 1 ; inline\ninc eax\njnz start\nret\n",
        "first:\nadd eax, 1\njne first\nsecond:\nmul ebx\njmp second\nret\n",
        "mov eax, 0\ncmp eax, 2\nje later\nsub eax, 1\nlater:\ncall target\nunknown_op eax\nret\n",
        "\n ; comment\nlabel_x:\npush eax\npop ebx\njz label_x\ndiv ecx\n",
    ]
    for code in cases:
        expected = _expected_score(code)
        response = stub.AnalyzeSnippet(pb2.SnippetRequest(code=code), timeout=5)
        assert math.isclose(response.score, expected, rel_tol=1e-6, abs_tol=1e-5), (
            f"AnalyzeSnippet returned {response.score}, expected {expected}, for:\n{code}"
        )
        assert proc.poll() is None


def test_client_processes_runtime_snippets_and_formats_results(running_service):
    proc, _, _, _ = running_service
    snippets = HOME / "snippets"
    results = HOME / "results.log"
    backup_root = Path(tempfile.mkdtemp(prefix="client-verifier-"))
    backup_snippets = backup_root / "snippets"
    had_results = results.exists()
    old_results = results.read_bytes() if had_results else None

    shutil.move(str(snippets), str(backup_snippets))
    snippets.mkdir()
    token = uuid.uuid4().hex[:10]
    runtime_cases = {
        f"a_{token}.asm": "entry:\nmov eax, 1\nadd eax, 2\njne entry\nret\n",
        f"m_{token}.asm": "; only comment\nforward:\npush eax\ncall fn\nret\n",
        f"z_{token}.asm": "top:\ninc eax\njnz top\ndec ebx\njmp top\n",
    }
    try:
        for name, code in runtime_cases.items():
            (snippets / name).write_text(code)

        run = subprocess.run(
            [sys.executable, "/home/user/client.py"],
            cwd="/home/user",
            env={**os.environ, "PYTHONPATH": "/home/user"},
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
        )
        assert run.returncode == 0, f"client.py failed:\n{run.stdout}\n{run.stderr}"
        assert results.is_file(), "client.py did not create results.log"
        expected = "\n".join(
            f"{name}: {_expected_score(runtime_cases[name]):.2f}"
            for name in sorted(runtime_cases)
        )
        assert results.read_text().strip() == expected
        assert proc.poll() is None, "server.py stopped while client.py was running"
    finally:
        shutil.rmtree(snippets, ignore_errors=True)
        shutil.move(str(backup_snippets), str(snippets))
        if had_results:
            results.write_bytes(old_results)
        elif results.exists():
            results.unlink()
        shutil.rmtree(backup_root, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
