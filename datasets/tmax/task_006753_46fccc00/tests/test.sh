#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import secrets
import shutil
import subprocess
import tarfile
import tempfile
import uuid
import zipfile

import pytest

CURATED_DIR = "/home/user/curated"
MANIFEST_PATH = os.path.join(CURATED_DIR, "manifest.jsonl")
SCRIPT_PATH = "/home/user/curate.py"
STAGING_DIR = "/home/user/staging"


def _normalize_member(name):
    while name.startswith("./"):
        name = name[2:]
    return name.rstrip("/")


def _archive_contents(path):
    contents = {}
    if path.endswith(".zip"):
        with zipfile.ZipFile(path) as archive:
            for info in archive.infolist():
                name = _normalize_member(info.filename)
                if not name:
                    continue
                if info.is_dir():
                    contents[name] = ("dir", None)
                else:
                    contents[name] = ("file", archive.read(info))
    else:
        with tarfile.open(path, "r:*") as archive:
            for member in archive.getmembers():
                name = _normalize_member(member.name)
                if not name:
                    continue
                if member.isdir():
                    contents[name] = ("dir", None)
                elif member.isfile():
                    extracted = archive.extractfile(member)
                    contents[name] = ("file", extracted.read())
    return contents


def _uncompressed_tar_contents(path):
    with open(path, "rb") as stream:
        magic = stream.read(6)
    assert not magic.startswith(b"\x1f\x8b"), f"{path} is gzip-compressed"
    assert not magic.startswith(b"BZh"), f"{path} is bzip2-compressed"
    assert not magic.startswith(b"\xfd7zXZ\x00"), f"{path} is xz-compressed"

    contents = {}
    with tarfile.open(path, "r:") as archive:
        for member in archive.getmembers():
            name = _normalize_member(member.name)
            if not name:
                continue
            if member.isdir():
                contents[name] = ("dir", None)
            elif member.isfile():
                extracted = archive.extractfile(member)
                contents[name] = ("file", extracted.read())
    return contents


def test_script_exists_and_uses_flock():
    assert os.path.isfile(SCRIPT_PATH), f"Required script {SCRIPT_PATH} is missing."
    with open(SCRIPT_PATH, "r", encoding="utf-8") as stream:
        source = stream.read()
    tree = ast.parse(source, filename=SCRIPT_PATH)

    module_aliases = set()
    direct_flock_names = set()
    direct_lock_ex_names = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for item in node.names:
                if item.name == "fcntl":
                    module_aliases.add(item.asname or "fcntl")
        elif isinstance(node, ast.ImportFrom) and node.module == "fcntl":
            for item in node.names:
                if item.name == "flock":
                    direct_flock_names.add(item.asname or "flock")
                elif item.name == "LOCK_EX":
                    direct_lock_ex_names.add(item.asname or "LOCK_EX")

    calls_flock = False
    references_lock_ex = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            if isinstance(node.func, ast.Attribute) and node.func.attr == "flock" and isinstance(node.func.value, ast.Name) and node.func.value.id in module_aliases:
                calls_flock = True
            if isinstance(node.func, ast.Name) and node.func.id in direct_flock_names:
                calls_flock = True
        if isinstance(node, ast.Attribute) and node.attr == "LOCK_EX" and isinstance(node.value, ast.Name) and node.value.id in module_aliases:
            references_lock_ex = True
        if isinstance(node, ast.Name) and node.id in direct_lock_ex_names:
            references_lock_ex = True

    assert calls_flock, "curate.py must call fcntl.flock"
    assert references_lock_ex, "curate.py must acquire an exclusive LOCK_EX lock"


def test_curated_files_exist():
    # Expected to be curated (author: alice)
    expected_files = ["app_v1.tar", "tool_v3.tar"]
    for f in expected_files:
        path = os.path.join(CURATED_DIR, f)
        assert os.path.isfile(path), f"Expected curated file {path} is missing."


def test_unapproved_files_do_not_exist():
    # Expected NOT to be curated (author: bob, charlie)
    unexpected_files = ["lib_v2.tar", "app_v2.tar", "lib_v2.tar.gz.tar", "app_v2.zip.tar"]
    for f in unexpected_files:
        path = os.path.join(CURATED_DIR, f)
        assert not os.path.exists(path), f"Unapproved artifact was curated: {path}"


def test_tar_contents_app_v1():
    tar_path = os.path.join(CURATED_DIR, "app_v1.tar")
    assert os.path.exists(tar_path), f"File {tar_path} not found."

    with tarfile.open(tar_path, "r") as tar:
        members = tar.getnames()
        # Ensure it contains the expected files
        assert "meta.json" in members or "./meta.json" in members, "meta.json missing in app_v1.tar"
        assert "bin/execute" in members or "./bin/execute" in members, "bin/execute missing in app_v1.tar"

    assert _uncompressed_tar_contents(tar_path) == _archive_contents(os.path.join(STAGING_DIR, "app_v1.zip"))


def test_tar_contents_tool_v3():
    tar_path = os.path.join(CURATED_DIR, "tool_v3.tar")
    assert os.path.exists(tar_path), f"File {tar_path} not found."

    with tarfile.open(tar_path, "r") as tar:
        members = tar.getnames()
        # Ensure it contains the expected files
        assert "meta.json" in members or "./meta.json" in members, "meta.json missing in tool_v3.tar"
        assert "src/tool.py" in members or "./src/tool.py" in members, "src/tool.py missing in tool_v3.tar"

    assert _uncompressed_tar_contents(tar_path) == _archive_contents(os.path.join(STAGING_DIR, "tool_v3.tar.bz2"))


def test_manifest_contents():
    assert os.path.isfile(MANIFEST_PATH), f"Manifest file {MANIFEST_PATH} is missing."

    with open(MANIFEST_PATH, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 lines in manifest.jsonl, found {len(lines)}."

    records = []
    for line in lines:
        try:
            records.append(json.loads(line))
        except json.JSONDecodeError:
            pytest.fail(f"Invalid JSON in manifest.jsonl: {line}")

    expected_records = [
        {"original": "app_v1.zip", "curated": "app_v1.tar", "build": 101},
        {"original": "tool_v3.tar.bz2", "curated": "tool_v3.tar", "build": 103}
    ]

    for expected in expected_records:
        assert expected in records, f"Expected record {expected} missing from manifest.jsonl"


def _clear_curated():
    os.makedirs(CURATED_DIR, exist_ok=True)
    for name in os.listdir(CURATED_DIR):
        path = os.path.join(CURATED_DIR, name)
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)


def _make_archive(path, author, build, payload):
    root = tempfile.mkdtemp(prefix="curate-input-")
    try:
        os.makedirs(os.path.join(root, "pkg", "empty"))
        with open(os.path.join(root, "meta.json"), "w", encoding="utf-8") as stream:
            json.dump({"author": author, "build": build}, stream)
        with open(os.path.join(root, "pkg", "data.bin"), "wb") as stream:
            stream.write(payload)
        with open(os.path.join(root, "top.txt"), "wb") as stream:
            stream.write(b"top-" + payload[:64])

        if path.endswith(".zip"):
            with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
                for current, dirs, files in os.walk(root):
                    for directory in dirs:
                        full = os.path.join(current, directory)
                        rel = os.path.relpath(full, root).replace(os.sep, "/") + "/"
                        archive.writestr(rel, b"")
                    for filename in files:
                        full = os.path.join(current, filename)
                        archive.write(full, os.path.relpath(full, root).replace(os.sep, "/"))
        else:
            mode = "w:gz" if path.endswith(".tar.gz") else "w:bz2"
            with tarfile.open(path, mode) as archive:
                archive.add(root, arcname=".")
    finally:
        shutil.rmtree(root)


def test_dynamic_concurrent_execution_and_argument_contract():
    _clear_curated()

    no_args = subprocess.run(["python3", SCRIPT_PATH], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
    assert no_args.returncode != 0, "curate.py must reject invocation with no archive argument"
    two_args = subprocess.run(["python3", SCRIPT_PATH, "/tmp/a", "/tmp/b"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
    assert two_args.returncode != 0, "curate.py must reject invocation with more than one argument"
    _clear_curated()

    token = uuid.uuid4().hex
    inputs = []
    expected_records = []
    expected_contents = {}
    unapproved_outputs = []
    extensions = [".zip", ".tar.gz", ".tar.bz2"]

    for index in range(18):
        extension = extensions[index % len(extensions)]
        author = "alice" if index % 3 != 1 else ("bob" if index % 2 else "charlie")
        build = 100000 + secrets.randbelow(800000)
        base = f"verify_{token}_{index}"
        archive_path = os.path.join(STAGING_DIR, base + extension)
        payload = secrets.token_bytes(131072 + index)
        _make_archive(archive_path, author, build, payload)
        inputs.append((archive_path, author))

        output_name = base + ".tar"
        if author == "alice":
            expected_records.append({"original": os.path.basename(archive_path), "curated": output_name, "build": build})
            expected_contents[output_name] = _archive_contents(archive_path)
        else:
            unapproved_outputs.append(output_name)

    gate = os.path.join("/tmp", f"curate-gate-{token}")
    command = 'while [ ! -e "$1" ]; do sleep 0.01; done; exec python3 "$2" "$3"'
    processes = []
    for archive_path, author in inputs:
        process = subprocess.Popen(
            ["bash", "-c", command, "curate-verifier", gate, SCRIPT_PATH, archive_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        processes.append((process, archive_path, author))

    with open(gate, "w", encoding="utf-8") as stream:
        stream.write("go")

    for process, archive_path, author in processes:
        stdout, stderr = process.communicate(timeout=30)
        assert process.returncode == 0, f"curate.py failed for {archive_path}: {stderr.decode(errors='replace')}"
        if author != "alice":
            assert stdout == b"" and stderr == b"", f"Unapproved archive {archive_path} did not exit silently"

    for output_name, expected in expected_contents.items():
        output_path = os.path.join(CURATED_DIR, output_name)
        assert os.path.isfile(output_path), f"Concurrent execution did not create {output_name}"
        assert _uncompressed_tar_contents(output_path) == expected, f"{output_name} did not preserve every archive member and its contents"

    for output_name in unapproved_outputs:
        assert not os.path.exists(os.path.join(CURATED_DIR, output_name)), f"Unapproved dynamic artifact was curated: {output_name}"

    assert os.path.isfile(MANIFEST_PATH), "Concurrent execution did not create manifest.jsonl"
    with open(MANIFEST_PATH, "r", encoding="utf-8") as stream:
        manifest_lines = [line.strip() for line in stream if line.strip()]
    assert len(manifest_lines) == len(expected_records), "Manifest has missing, duplicate, or unexpected lines"
    parsed = [json.loads(line) for line in manifest_lines]
    assert all(set(record) == {"original", "curated", "build"} for record in parsed), "Manifest records have incorrect fields"
    assert sorted(parsed, key=lambda item: item["original"]) == sorted(expected_records, key=lambda item: item["original"])
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
