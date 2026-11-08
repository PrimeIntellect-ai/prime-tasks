#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import difflib
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import uuid
from pathlib import Path

import pytest

DIR_SYNC_PATH = "/home/user/dir_sync"
PROTO_FILE = os.path.join(DIR_SYNC_PATH, "sync.proto")
E2E_SCRIPT = os.path.join(DIR_SYNC_PATH, "run_e2e.sh")
SERVER_FILE = os.path.join(DIR_SYNC_PATH, "server.py")
CLIENT_FILE = os.path.join(DIR_SYNC_PATH, "client.py")


def test_files_exist():
    assert os.path.isdir(DIR_SYNC_PATH), f"{DIR_SYNC_PATH} does not exist"
    assert os.path.isfile(PROTO_FILE), f"{PROTO_FILE} does not exist"
    assert os.path.isfile(E2E_SCRIPT), f"{E2E_SCRIPT} does not exist"
    assert os.path.isfile(SERVER_FILE), f"{SERVER_FILE} does not exist"
    assert os.path.isfile(CLIENT_FILE), f"{CLIENT_FILE} does not exist"


def test_proto_contract():
    subprocess.run([
        sys.executable, "-m", "grpc_tools.protoc",
        f"-I{DIR_SYNC_PATH}",
        f"--python_out={DIR_SYNC_PATH}",
        f"--grpc_python_out={DIR_SYNC_PATH}",
        PROTO_FILE,
    ], check=True)
    sys.path.insert(0, DIR_SYNC_PATH)
    import sync_pb2

    desc = sync_pb2.DESCRIPTOR
    assert desc.package == "sync"
    service = desc.services_by_name.get("DirSync")
    assert service is not None
    assert [(m.name, m.input_type.name, m.output_type.name) for m in service.methods] == [
        ("CalculateDiff", "DiffRequest", "DiffResponse"),
        ("ApplyPatch", "PatchRequest", "PatchResponse"),
    ]
    assert [(f.name, f.number, f.type, f.label) for f in desc.message_types_by_name["DiffRequest"].fields] == [
        ("source_dir", 1, 9, 1), ("target_dir", 2, 9, 1)
    ]
    assert [(f.name, f.number, f.type, f.label) for f in desc.message_types_by_name["DiffResponse"].fields] == [
        ("patch_lines", 1, 9, 3)
    ]
    assert [(f.name, f.number, f.type, f.label) for f in desc.message_types_by_name["PatchRequest"].fields] == [
        ("target_dir", 1, 9, 1), ("patch_lines", 2, 9, 3)
    ]
    assert [(f.name, f.number, f.type, f.label) for f in desc.message_types_by_name["PatchResponse"].fields] == [
        ("success", 1, 8, 1)
    ]


def test_server_contains_custom_recursive_pruning_structure():
    source = Path(SERVER_FILE).read_text(encoding="utf-8")
    tree = ast.parse(source)
    assert any(isinstance(n, ast.ClassDef) for n in ast.walk(tree)), \
        "server.py must define a custom tree/node data structure"

    functions = [n for n in ast.walk(tree) if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))]
    recursive = False
    for fn in functions:
        for node in ast.walk(fn):
            if isinstance(node, ast.Call):
                called = node.func
                if isinstance(called, ast.Name) and called.id == fn.name:
                    recursive = True
                if isinstance(called, ast.Attribute) and called.attr == fn.name:
                    recursive = True
    assert recursive, "tree construction/comparison must recurse through directory subtrees"

    identifiers = {n.id.lower() for n in ast.walk(tree) if isinstance(n, ast.Name)}
    identifiers |= {n.attr.lower() for n in ast.walk(tree) if isinstance(n, ast.Attribute)}
    assert any(any(token in name for token in ("hash", "digest", "mtime", "size", "content")) for name in identifiers), \
        "tree nodes must hash or compare file metadata/content"
    assert any(isinstance(n, ast.Compare) and any(isinstance(op, (ast.Eq, ast.NotEq)) for op in n.ops)
               for n in ast.walk(tree)), "tree comparison must compare node values to prune unchanged subtrees"


def test_e2e_script_executable_and_passes():
    st = os.stat(E2E_SCRIPT)
    assert bool(st.st_mode & stat.S_IXUSR), f"{E2E_SCRIPT} is not executable"
    result = subprocess.run(
        ["bash", E2E_SCRIPT], cwd=DIR_SYNC_PATH, capture_output=True, text=True, timeout=90
    )
    assert result.returncode == 0, (
        f"run_e2e.sh failed with code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )
    assert "E2E TEST PASSED" in result.stdout, \
        "run_e2e.sh did not output 'E2E TEST PASSED'"


def write_tree(root, files):
    root = Path(root)
    root.mkdir(parents=True, exist_ok=True)
    for rel, data in files.items():
        path = root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(data, encoding="utf-8")


def tree_contents(root):
    root = Path(root)
    result = {}
    for path in root.rglob("*"):
        if path.is_file():
            result[path.relative_to(root).as_posix()] = path.read_bytes()
    return result


def patch_text(lines):
    lines = list(lines)
    if not lines:
        return ""
    if all("\n" not in line and "\r" not in line for line in lines):
        return "\n".join(lines) + "\n"
    return "".join(lines)


def assert_safe_unified_diff(lines):
    text = patch_text(lines)
    split = text.splitlines()
    old_headers = [line for line in split if line.startswith("--- ")]
    new_headers = [line for line in split if line.startswith("+++ ")]
    assert old_headers and len(old_headers) == len(new_headers), \
        f"response is not a combined unified diff:\n{text}"
    assert any(line.startswith("@@ ") for line in split), "unified diff has no hunks"
    for header in old_headers + new_headers:
        path = header[4:].split("\t", 1)[0]
        if path == "/dev/null":
            continue
        assert path and not os.path.isabs(path), f"patch path is absolute: {path}"
        parts = Path(path).parts
        assert ".." not in parts, f"patch path escapes the directory root: {path}"
    return text


def assert_system_patch_reproduces(source_dir, expected, text):
    successes = []
    for strip in (0, 1):
        candidate = tempfile.mkdtemp(prefix="dir_sync_patch_check_")
        shutil.rmtree(candidate)
        shutil.copytree(source_dir, candidate)
        try:
            proc = subprocess.run(
                ["patch", "--batch", "--forward", f"-p{strip}"],
                cwd=candidate, input=text, text=True, capture_output=True, timeout=20
            )
            if proc.returncode == 0 and tree_contents(candidate) == expected:
                successes.append(strip)
        finally:
            shutil.rmtree(candidate, ignore_errors=True)
    assert successes, "patch_lines are not a valid, self-contained unified diff applicable by patch"


def test_grpc_server_functionality():
    subprocess.run([
        sys.executable, "-m", "grpc_tools.protoc",
        f"-I{DIR_SYNC_PATH}",
        f"--python_out={DIR_SYNC_PATH}",
        f"--grpc_python_out={DIR_SYNC_PATH}",
        PROTO_FILE,
    ], check=True)
    sys.path.insert(0, DIR_SYNC_PATH)
    try:
        import grpc
        import sync_pb2
        import sync_pb2_grpc
    except ImportError as exc:
        pytest.fail(f"Failed to import generated protobuf modules: {exc}")

    # Remove a server accidentally left behind by run_e2e.sh before starting the artifact ourselves.
    subprocess.run(["pkill", "-f", "^.*python.*?/home/user/dir_sync/server.py$"], check=False)
    time.sleep(0.3)
    server_process = subprocess.Popen(
        [sys.executable, SERVER_FILE], cwd=DIR_SYNC_PATH,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    channel = grpc.insecure_channel("localhost:50051")
    roots = []
    try:
        try:
            grpc.channel_ready_future(channel).result(timeout=10)
        except Exception:
            stdout, stderr = server_process.communicate(timeout=2)
            pytest.fail(f"Server failed to start. Stdout: {stdout}, Stderr: {stderr}")
        assert server_process.poll() is None, "server.py exited unexpectedly"
        stub = sync_pb2_grpc.DirSyncStub(channel)

        # Retain the original fixed case, but validate its returned artifact independently.
        cases = [
            (
                {"file1.txt": "Hello World\nLine 2\n"},
                {"file1.txt": "Hello World\nLine 2 Modified\n", "file2.txt": "New file\n"},
            ),
            (
                {
                    "unchanged.txt": "same\n" * 20,
                    "nested/deeper/change.txt": "old alpha\nold beta\n",
                    "remove_" + uuid.uuid4().hex + ".txt": "delete me\n",
                    "nested/stable.txt": "stable\n",
                },
                {
                    "unchanged.txt": "same\n" * 20,
                    "nested/deeper/change.txt": "new alpha\nold beta\nextra\n",
                    "add_" + uuid.uuid4().hex + ".txt": "created dynamically\n",
                    "nested/stable.txt": "stable\n",
                    "brand/new/path/file.txt": "nested addition\n",
                },
            ),
            (
                {"x.txt": "one\ntwo\nthree\n", "gone/sub.txt": "gone\n"},
                {"x.txt": "zero\none\nthree changed\n", "fresh.txt": "fresh\n"},
            ),
        ]

        for index, (source_files, target_files) in enumerate(cases):
            base = tempfile.mkdtemp(prefix=f"grpc_dynamic_{index}_")
            roots.append(base)
            source_dir = os.path.join(base, "source_" + uuid.uuid4().hex)
            target_dir = os.path.join(base, "target_" + uuid.uuid4().hex)
            expected_dir = os.path.join(base, "expected")
            write_tree(source_dir, source_files)
            write_tree(target_dir, target_files)
            shutil.copytree(target_dir, expected_dir)
            expected = tree_contents(expected_dir)

            diff_resp = stub.CalculateDiff(
                sync_pb2.DiffRequest(source_dir=source_dir, target_dir=target_dir), timeout=20
            )
            assert len(diff_resp.patch_lines) > 0, "Expected patch lines but got none"
            text = assert_safe_unified_diff(diff_resp.patch_lines)
            assert_system_patch_reproduces(source_dir, expected, text)

            # The target/oracle is removed before ApplyPatch, preventing copying from it.
            shutil.rmtree(target_dir)
            patch_resp = stub.ApplyPatch(
                sync_pb2.PatchRequest(target_dir=source_dir, patch_lines=diff_resp.patch_lines), timeout=20
            )
            assert patch_resp.success is True, "ApplyPatch returned success=False"
            diff_result = subprocess.run(
                ["diff", "-r", source_dir, expected_dir], capture_output=True, text=True
            )
            assert diff_result.returncode == 0, \
                f"Directories do not match after patch: {diff_result.stdout}{diff_result.stderr}"

        # Equal trees must not produce a fabricated patch.
        base = tempfile.mkdtemp(prefix="grpc_equal_")
        roots.append(base)
        equal_a = os.path.join(base, "a")
        equal_b = os.path.join(base, "b")
        equal_files = {"nested/same.txt": "identical\n", "also.txt": "same too\n"}
        write_tree(equal_a, equal_files)
        write_tree(equal_b, equal_files)
        equal_resp = stub.CalculateDiff(
            sync_pb2.DiffRequest(source_dir=equal_a, target_dir=equal_b), timeout=20
        )
        assert list(equal_resp.patch_lines) == [], "identical directories should yield no patch lines"

        # Exercise ApplyPatch with a verifier-generated patch, independent of CalculateDiff.
        base = tempfile.mkdtemp(prefix="grpc_external_patch_")
        roots.append(base)
        apply_dir = os.path.join(base, "apply")
        write_tree(apply_dir, {"random.txt": "before\nline two\n"})
        generated = list(difflib.unified_diff(
            ["before\n", "line two\n"],
            ["after " + uuid.uuid4().hex + "\n", "line two\n", "added\n"],
            fromfile="random.txt", tofile="random.txt"
        ))
        response = stub.ApplyPatch(
            sync_pb2.PatchRequest(target_dir=apply_dir, patch_lines=generated), timeout=20
        )
        assert response.success is True, "ApplyPatch rejected a valid verifier-generated unified diff"
        assert Path(apply_dir, "random.txt").read_text() == \
            "".join([line[1:] for line in generated if line.startswith("+") and not line.startswith("+++")]) or \
            Path(apply_dir, "random.txt").read_text().startswith("after ")
        content = Path(apply_dir, "random.txt").read_text()
        assert content.startswith("after ") and content.endswith("line two\nadded\n")

    finally:
        channel.close()
        if server_process.poll() is None:
            server_process.terminate()
            try:
                server_process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                server_process.kill()
                server_process.wait(timeout=5)
        for root in roots:
            shutil.rmtree(root, ignore_errors=True)
        shutil.rmtree("/tmp/grpc_test_source", ignore_errors=True)
        shutil.rmtree("/tmp/grpc_test_target", ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
