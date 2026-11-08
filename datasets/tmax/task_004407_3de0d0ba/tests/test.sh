#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import importlib
import json
import math
import os
import pathlib
import signal
import subprocess
import sys
import tempfile
import time

import grpc
import pytest
from google.protobuf.descriptor import FieldDescriptor

PARSER_SOURCE = "/home/user/build_tools/manifest_parser.cpp"
PARSER_BIN = "/home/user/build_tools/parser_bin"
PROTO_PATH = "/home/user/pipeline/build_service.proto"
PIPELINE_DIR = pathlib.Path("/home/user/pipeline")
JSON_PATH = PIPELINE_DIR / "resolution.json"
REQUESTED = ["Core", "UI", "Network", "Database"]


def validate_values(versions, score):
    assert set(versions) == set(REQUESTED), f"Unexpected version keys: {set(versions)}"
    c = versions.get("Core")
    u = versions.get("UI")
    n = versions.get("Network")
    d = versions.get("Database")

    for name, value in versions.items():
        assert isinstance(value, int) and not isinstance(value, bool), f"{name} version must be an integer."

    assert c in {1, 2, 3}, f"Core version {c} is not in allowed set {{1, 2, 3}}"
    assert u in {1, 2}, f"UI version {u} is not in allowed set {{1, 2}}"
    assert n in {2, 3}, f"Network version {n} is not in allowed set {{2, 3}}"
    assert d in {1, 2, 3}, f"Database version {d} is not in allowed set {{1, 2, 3}}"
    assert n == d, f"Network ({n}) and Database ({d}) versions must match."
    assert sum([c, u, n, d]) == 9, f"Sum of versions must be 9, got {sum([c, u, n, d])}."
    if u == 2:
        assert c >= 2, f"If UI=2, Core must be >= 2. Got Core={c}."

    assert isinstance(score, (int, float)) and not isinstance(score, bool), "Score must be numeric."
    expected_score = (c * 1.5) + (u * 2.5) + (n * 3.5) + (d * 4.5)
    assert math.isclose(float(score), expected_score, rel_tol=0, abs_tol=1e-9), \
        f"Expected score {expected_score}, got {score}."


def load_and_validate_json(path=JSON_PATH):
    assert path.is_file(), f"Output JSON file {path} does not exist."
    try:
        with path.open("r") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {path} is not valid JSON.")
    assert isinstance(data, dict), "Resolution JSON must contain an object."
    assert "versions" in data, "Key 'versions' missing from JSON."
    assert "score" in data, "Key 'score' missing from JSON."
    assert set(data) == {"versions", "score"}, f"Unexpected top-level JSON keys: {set(data)}"
    assert isinstance(data["versions"], dict), "'versions' must be a JSON object."
    validate_values(data["versions"], data["score"])
    return data


def test_parser_bin_exists_and_runs_safely():
    assert os.path.isfile(PARSER_BIN), f"Expected compiled binary at {PARSER_BIN} does not exist."
    assert os.access(PARSER_BIN, os.X_OK), f"The file {PARSER_BIN} is not executable."
    with open(PARSER_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "parser_bin must be a compiled ELF binary."

    result = subprocess.run([PARSER_BIN], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, f"parser_bin failed: {result.stdout}\n{result.stderr}"
    assert "Parsed: Manifest_V1" in result.stdout, "parser_bin did not parse its manifest input correctly."

    assert os.path.isfile(PARSER_SOURCE), f"Expected source file {PARSER_SOURCE} does not exist."
    with tempfile.TemporaryDirectory() as td:
        sanitized_bin = os.path.join(td, "parser_sanitized")
        compile_result = subprocess.run(
            ["g++", "-std=c++17", "-g", "-O1", "-fno-omit-frame-pointer",
             "-fsanitize=address,undefined", PARSER_SOURCE, "-o", sanitized_bin],
            capture_output=True, text=True, timeout=30)
        assert compile_result.returncode == 0, \
            f"The repaired parser source does not compile: {compile_result.stderr}"
        env = os.environ.copy()
        env["ASAN_OPTIONS"] = "detect_leaks=1:halt_on_error=1:abort_on_error=1"
        env["UBSAN_OPTIONS"] = "halt_on_error=1:print_stacktrace=1"
        run_result = subprocess.run(
            [sanitized_bin], capture_output=True, text=True, env=env, timeout=10)
        assert run_result.returncode == 0, \
            f"Sanitizers detected memory errors or leaks:\n{run_result.stdout}\n{run_result.stderr}"
        assert "Parsed: Manifest_V1" in run_result.stdout


def compile_and_load_proto():
    td = tempfile.TemporaryDirectory()
    result = subprocess.run(
        [sys.executable, "-m", "grpc_tools.protoc", "-I" + str(PIPELINE_DIR),
         "--python_out=" + td.name, "--grpc_python_out=" + td.name, PROTO_PATH],
        capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, f"Invalid protobuf definition: {result.stderr}"
    sys.path.insert(0, td.name)
    importlib.invalidate_caches()
    pb2 = importlib.import_module("build_service_pb2")
    pb2_grpc = importlib.import_module("build_service_pb2_grpc")
    return td, pb2, pb2_grpc


def test_protobuf_file_and_live_service():
    assert os.path.isfile(PROTO_PATH), f"Protobuf file {PROTO_PATH} does not exist."
    with open(PROTO_PATH, "r") as f:
        content = f.read()
    assert "DependencyResolver" in content, "Service DependencyResolver not found in proto file."
    assert "ResolveBuild" in content, "RPC method ResolveBuild not found in proto file."
    assert "ResolveRequest" in content, "Message ResolveRequest not found in proto file."
    assert "ResolveResponse" in content, "Message ResolveResponse not found in proto file."

    td, pb2, pb2_grpc = compile_and_load_proto()
    try:
        request_desc = pb2.ResolveRequest.DESCRIPTOR
        response_desc = pb2.ResolveResponse.DESCRIPTOR
        req_field = request_desc.fields_by_name.get("requested_modules")
        assert req_field is not None
        assert req_field.type == FieldDescriptor.TYPE_STRING
        assert req_field.label == FieldDescriptor.LABEL_REPEATED

        versions_field = response_desc.fields_by_name.get("resolved_versions")
        assert versions_field is not None and versions_field.type == FieldDescriptor.TYPE_MESSAGE
        assert versions_field.message_type.GetOptions().map_entry, "resolved_versions must be a protobuf map."
        key_field = versions_field.message_type.fields_by_name["key"]
        value_field = versions_field.message_type.fields_by_name["value"]
        assert key_field.type == FieldDescriptor.TYPE_STRING
        assert value_field.type == FieldDescriptor.TYPE_INT32
        score_field = response_desc.fields_by_name.get("build_priority_score")
        assert score_field is not None and score_field.type == FieldDescriptor.TYPE_DOUBLE

        services = [s for s in pb2.DESCRIPTOR.services_by_name.values() if s.name == "DependencyResolver"]
        assert len(services) == 1, "Exactly one DependencyResolver service is required."
        method = services[0].methods_by_name.get("ResolveBuild")
        assert method is not None, "ResolveBuild RPC is missing."
        assert method.input_type.full_name == request_desc.full_name
        assert method.output_type.full_name == response_desc.full_name

        channel = grpc.insecure_channel("localhost:50051")
        grpc.channel_ready_future(channel).result(timeout=8)
        stub = pb2_grpc.DependencyResolverStub(channel)
        response = stub.ResolveBuild(pb2.ResolveRequest(requested_modules=REQUESTED), timeout=8)
        validate_values(dict(response.resolved_versions), response.build_priority_score)
        channel.close()
    finally:
        td.cleanup()


def test_resolution_json():
    load_and_validate_json()


def client_candidates():
    preferred = []
    fallback = []
    for path in PIPELINE_DIR.rglob("*"):
        if not path.is_file() or path in {JSON_PATH, pathlib.Path(PROTO_PATH)}:
            continue
        if path.name.endswith(("_pb2.py", "_pb2_grpc.py")):
            continue
        try:
            text = path.read_text(errors="ignore")
        except OSError:
            continue
        if "resolution.json" not in text or "ResolveBuild" not in text:
            continue
        if path.suffix not in {".py", ".sh"} and not text.startswith("#!"):
            continue
        (preferred if "client" in path.name.lower() else fallback).append(path)
    return sorted(preferred) + sorted(fallback)


def run_script(path):
    if path.suffix == ".py":
        cmd = [sys.executable, str(path)]
    elif path.suffix == ".sh":
        cmd = ["bash", str(path)]
    else:
        cmd = [str(path)]
    proc = subprocess.Popen(cmd, cwd=str(PIPELINE_DIR), stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True, start_new_session=True)
    try:
        out, err = proc.communicate(timeout=12)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        out, err = proc.communicate()
        return -1, out, err
    return proc.returncode, out, err


def listener_pids(port):
    wanted = f"{port:04X}"
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = pathlib.Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            cols = line.split()
            if len(cols) > 9 and cols[1].rsplit(":", 1)[-1].upper() == wanted and cols[3] == "0A":
                inodes.add(cols[9])
    pids = set()
    for procdir in pathlib.Path("/proc").iterdir():
        if not procdir.name.isdigit():
            continue
        try:
            for fd in (procdir / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(procdir.name))
        except OSError:
            continue
    return pids


def test_client_actually_contacts_server():
    candidates = client_candidates()
    assert candidates, "No client script that invokes ResolveBuild and writes resolution.json was found."

    chosen = None
    valid_bytes = None
    diagnostics = []
    for candidate in candidates:
        JSON_PATH.unlink(missing_ok=True)
        rc, out, err = run_script(candidate)
        try:
            if rc == 0:
                load_and_validate_json()
                chosen = candidate
                valid_bytes = JSON_PATH.read_bytes()
                break
        except AssertionError as exc:
            diagnostics.append(f"{candidate}: {exc}")
        diagnostics.append(f"{candidate}: exit={rc}, stdout={out!r}, stderr={err!r}")
    assert chosen is not None, "No client script successfully called the service and produced valid JSON. " + " | ".join(diagnostics)

    pids = listener_pids(50051)
    assert pids, "Could not identify the running gRPC server on port 50051."
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(1)
    for pid in pids:
        try:
            os.kill(pid, 0)
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass

    JSON_PATH.unlink(missing_ok=True)
    rc, out, err = run_script(chosen)
    produced_valid = False
    if rc == 0 and JSON_PATH.is_file():
        try:
            load_and_validate_json()
            produced_valid = True
        except AssertionError:
            pass
    JSON_PATH.write_bytes(valid_bytes)
    assert not produced_valid, \
        "The client still fabricated a valid resolution when the gRPC server was unavailable."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
