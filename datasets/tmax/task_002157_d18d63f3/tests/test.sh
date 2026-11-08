#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import difflib
import os
import re
import secrets
import subprocess
import sys
import tempfile

import grpc


def compile_proto(tmpdir):
    proto_path = "/app/artifact.proto"
    assert os.path.isfile(proto_path), "/app/artifact.proto does not exist"
    result = subprocess.run([
        sys.executable, "-m", "grpc_tools.protoc",
        "-I/app",
        f"--python_out={tmpdir}",
        f"--grpc_python_out={tmpdir}",
        proto_path,
    ], capture_output=True, text=True)
    assert result.returncode == 0, f"Failed to compile protobuf:\n{result.stderr}"


def make_diff(original, patched):
    return "".join(difflib.unified_diff(
        original.splitlines(keepends=True),
        patched.splitlines(keepends=True),
        fromfile="a/artifact.txt",
        tofile="b/artifact.txt",
        n=2,
    ))


def generated_cases():
    # Preserve the original verifier's known request.
    yield (
        "Hello World\n",
        "--- a/file\n+++ b/file\n@@ -1 +1 @@\n-Hello World\n+Hello Universe\n",
        "Hello Universe\n",
    )

    # Runtime-generated contents prevent a fixed-response implementation from passing.
    for _ in range(5):
        token = secrets.token_hex(8)
        before = [f"{token}-line-{i}\n" for i in range(12)]
        after = list(before)
        after[2] = f"{token}-replacement-{secrets.token_hex(4)}\n"
        del after[5]
        after.insert(8, f"{token}-inserted-{secrets.token_hex(4)}\n")
        original = "".join(before)
        expected = "".join(after)
        yield original, make_diff(original, expected), expected


def test_proto_schema_and_nginx_configuration():
    assert os.path.isfile("/app/nginx.conf"), "/app/nginx.conf does not exist"
    result = subprocess.run(
        ["nginx", "-T", "-c", "/app/nginx.conf"],
        capture_output=True, text=True,
    )
    assert result.returncode == 0, f"Invalid nginx configuration:\n{result.stderr}"
    rendered = result.stdout + result.stderr
    assert re.search(r"listen\s+127\.0\.0\.1:8080\b[^;]*\bhttp2\b", rendered), \
        "Nginx must listen on 127.0.0.1:8080 with HTTP/2"
    assert re.search(r"grpc_pass\s+grpc://127\.0\.0\.1:50051\s*;", rendered), \
        "Nginx must proxy gRPC traffic to grpc://127.0.0.1:50051"

    nginx_running = False
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/comm", encoding="utf-8") as f:
                if f.read().strip() == "nginx":
                    nginx_running = True
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    assert nginx_running, "Nginx is not running"

    with tempfile.TemporaryDirectory() as tmpdir:
        compile_proto(tmpdir)
        sys.path.insert(0, tmpdir)
        try:
            import artifact_pb2
            descriptor = artifact_pb2.DESCRIPTOR
            assert descriptor.package == "artifact"
            service = descriptor.services_by_name.get("PatchService")
            assert service is not None
            assert len(service.methods) == 1 and service.methods[0].name == "ApplyPatch"

            request = descriptor.message_types_by_name.get("PatchRequest")
            response = descriptor.message_types_by_name.get("PatchResponse")
            assert request is not None and response is not None
            assert [(f.name, f.number, f.type) for f in request.fields] == [
                ("original_content", 1, f.TYPE_STRING),
                ("patch_content", 2, f.TYPE_STRING),
            ]
            assert [(f.name, f.number, f.type) for f in response.fields] == [
                ("patched_content", 1, f.TYPE_STRING),
            ]
        finally:
            sys.path.pop(0)
            sys.modules.pop("artifact_pb2", None)
            sys.modules.pop("artifact_pb2_grpc", None)


def test_vendored_package_applies_unified_diffs():
    patcher_path = "/app/vendored/patch_manager/patcher.py"
    assert os.path.isfile(patcher_path), f"{patcher_path} is missing"

    sys.path.insert(0, "/app/vendored")
    try:
        import patch_manager
        for original, patch, expected in generated_cases():
            actual = patch_manager.apply_diff(original, patch)
            assert actual == expected, \
                f"Vendored patch_manager produced {actual!r}, expected {expected!r}"
    finally:
        sys.path.pop(0)
        sys.modules.pop("patch_manager", None)
        sys.modules.pop("patch_manager.patcher", None)


def test_server_imports_and_calls_vendored_patch_manager():
    server_path = "/app/server.py"
    assert os.path.isfile(server_path), "/app/server.py does not exist"
    with open(server_path, encoding="utf-8") as f:
        tree = ast.parse(f.read(), filename=server_path)

    imports_patch_manager = False
    imported_function_names = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if "patch_manager" in alias.name.split("."):
                    imports_patch_manager = True
        elif isinstance(node, ast.ImportFrom):
            names = [alias.name for alias in node.names]
            if "patch_manager" in (node.module or "").split(".") or "patch_manager" in names:
                imports_patch_manager = True
            if "patch_manager" in (node.module or "").split("."):
                for alias in node.names:
                    if alias.name == "apply_diff":
                        imported_function_names.add(alias.asname or alias.name)

    calls_apply_diff = any(
        isinstance(node, ast.Call) and (
            (isinstance(node.func, ast.Attribute) and node.func.attr == "apply_diff") or
            (isinstance(node.func, ast.Name) and node.func.id in imported_function_names)
        )
        for node in ast.walk(tree)
    )
    assert imports_patch_manager, "server.py must import the vendored patch_manager"
    assert calls_apply_diff, "server.py must call patch_manager.apply_diff"


def test_grpc_service_directly_and_via_nginx():
    with tempfile.TemporaryDirectory() as tmpdir:
        compile_proto(tmpdir)
        sys.path.insert(0, tmpdir)
        try:
            import artifact_pb2
            import artifact_pb2_grpc

            channels = [
                grpc.insecure_channel("127.0.0.1:50051"),
                grpc.insecure_channel("127.0.0.1:8080"),
            ]
            try:
                for channel in channels:
                    grpc.channel_ready_future(channel).result(timeout=5)
                    stub = artifact_pb2_grpc.PatchServiceStub(channel)
                    for original, patch, expected in generated_cases():
                        request = artifact_pb2.PatchRequest(
                            original_content=original,
                            patch_content=patch,
                        )
                        response = stub.ApplyPatch(request, timeout=5)
                        assert response.patched_content == expected, \
                            f"Expected {expected!r}, got {response.patched_content!r}"

                    bad = artifact_pb2.PatchRequest(
                        original_content=f"unchanged-{secrets.token_hex(8)}\n",
                        patch_content="this is not a unified diff\n",
                    )
                    response = stub.ApplyPatch(bad, timeout=5)
                    assert response.patched_content == "", \
                        "A failed patch must return an empty string"
            finally:
                for channel in channels:
                    channel.close()
        finally:
            sys.path.pop(0)
            sys.modules.pop("artifact_pb2", None)
            sys.modules.pop("artifact_pb2_grpc", None)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
