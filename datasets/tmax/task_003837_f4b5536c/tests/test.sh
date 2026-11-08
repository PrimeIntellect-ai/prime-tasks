#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def test_restored_hello_txt():
    path = "/home/user/storage_task/restored/hello.txt"
    assert os.path.isfile(path), f"Restored file {path} does not exist"
    with open(path, "rb") as f:
        content = f.read()
    assert content == b"Hello World!", f"Expected 'Hello World!' in {path}, got {content}"

def test_restored_info_bin():
    path = "/home/user/storage_task/restored/data/info.bin"
    assert os.path.isfile(path), f"Restored file {path} does not exist"
    with open(path, "rb") as f:
        content = f.read()
    assert content == b"Data file content", f"Expected 'Data file content' in {path}, got {content}"

def test_rejected_log():
    path = "/home/user/storage_task/rejected.log"
    assert os.path.isfile(path), f"Rejected log file {path} does not exist"
    with open(path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_rejections = [
        "../escaped.txt",
        "/etc/fake_passwd",
        "data/../../root.txt"
    ]

    assert len(lines) == len(expected_rejections), f"Expected {len(expected_rejections)} rejected entries, got {len(lines)}"

    for expected in expected_rejections:
        assert expected in lines, f"Expected rejected path '{expected}' not found in {path}"

def test_no_escaped_files():
    # Verify that the malicious files were not actually written outside the restored directory
    escaped_paths = [
        "/home/user/storage_task/escaped.txt",
        "/etc/fake_passwd",
        "/home/user/root.txt"
    ]
    for path in escaped_paths:
        assert not os.path.exists(path), f"Malicious file was written to {path} despite security checks"
TEST_EOF

verify_all() {
    python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 || return 1

    project=/home/user/storage_task/restorer
    test -d "$project" || return 1
    test -f "$project/Cargo.toml" || return 1
    test -d "$project/src" || return 1
    find "$project/src" -type f -name '*.rs' -print -quit | grep -q . || return 1

    python3 - << 'PY_EOF' || return 1
import collections
import json
import os
import secrets
import shutil
import subprocess
import sys

workspace = "/home/user/storage_task"
project = os.path.join(workspace, "restorer")
manifest_path = os.path.join(workspace, "manifest.jsonl")
chunks_dir = os.path.join(workspace, "chunks")
restore_dir = os.path.join(workspace, "restored")
rejected_path = os.path.join(workspace, "rejected.log")
manifest_toml = os.path.realpath(os.path.join(project, "Cargo.toml"))

# Compile the submitted Cargo project and identify the binary produced by it.
build = subprocess.run(
    ["cargo", "build", "--message-format=json"],
    cwd=project,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
)
if build.stderr:
    sys.stderr.write(build.stderr)
assert build.returncode == 0, "cargo build failed"

metadata = subprocess.run(
    ["cargo", "metadata", "--no-deps", "--format-version", "1"],
    cwd=project,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
)
if metadata.stderr:
    sys.stderr.write(metadata.stderr)
assert metadata.returncode == 0, "cargo metadata failed"
meta = json.loads(metadata.stdout)
packages = [p for p in meta["packages"] if os.path.realpath(p["manifest_path"]) == manifest_toml]
assert len(packages) == 1, "Cargo.toml must define a buildable package"
package = packages[0]
bin_targets = [t for t in package["targets"] if "bin" in t.get("kind", [])]
assert bin_targets, "Cargo project does not contain a Rust binary target"
if package.get("default_run"):
    selected_name = package["default_run"]
else:
    assert len(bin_targets) == 1, "multiple binaries exist but package.default-run is not set"
    selected_name = bin_targets[0]["name"]

executables = []
for line in build.stdout.splitlines():
    try:
        message = json.loads(line)
    except json.JSONDecodeError:
        continue
    if message.get("reason") != "compiler-artifact":
        continue
    target = message.get("target", {})
    executable = message.get("executable")
    if executable and target.get("name") == selected_name and "bin" in target.get("kind", []):
        executables.append(executable)
assert executables, "cargo build did not produce the submitted Rust executable"
executable = executables[-1]
assert os.path.isfile(executable) and os.access(executable, os.X_OK), "built Rust artifact is not executable"

# Generate a fresh manifest only after compilation, so fixed final-state output cannot pass.
token = secrets.token_hex(10)
prefix = os.urandom(19)
suffix = os.urandom(23)
second_file = os.urandom(37)
bad_data = os.urandom(17)

chunk_names = {
    "prefix": f"part_{token}_p.bin",
    "suffix": f"part_{token}_s.bin",
    "second": f"part_{token}_d.bin",
    "bad": f"part_{token}_x.bin",
}
chunk_data = {
    chunk_names["prefix"]: prefix,
    chunk_names["suffix"]: suffix,
    chunk_names["second"]: second_file,
    chunk_names["bad"]: bad_data,
}
for name, data in chunk_data.items():
    with open(os.path.join(chunks_dir, name), "wb") as f:
        f.write(data)

safe_one = f"dynamic_{token}/combined.bin"
safe_two = f"dynamic_{token}/nested/data.bin"
malicious = [
    f"../escaped_{token}.bin",
    f"/tmp/storage_task_escape_{token}.bin",
    f"data/../../root_{token}.bin",
]
entries = [
    {"chunk": chunk_names["suffix"], "target": safe_one, "offset": len(prefix)},
    {"chunk": chunk_names["prefix"], "target": safe_one, "offset": 0},
    {"chunk": chunk_names["second"], "target": safe_two, "offset": 0},
    {"chunk": chunk_names["bad"], "target": malicious[0], "offset": 0},
    {"chunk": chunk_names["bad"], "target": malicious[1], "offset": 0},
    {"chunk": chunk_names["bad"], "target": malicious[2], "offset": 0},
]
with open(manifest_path, "w", encoding="utf-8") as f:
    for entry in entries:
        f.write(json.dumps(entry) + "\n")

# Remove all prior output after building, ensuring only execution of the artifact can restore it.
shutil.rmtree(restore_dir, ignore_errors=True)
if os.path.lexists(rejected_path):
    os.remove(rejected_path)
escaped_paths = [os.path.normpath(os.path.join(restore_dir, target)) for target in malicious]
for path in escaped_paths:
    if os.path.isdir(path) and not os.path.islink(path):
        shutil.rmtree(path)
    elif os.path.lexists(path):
        os.remove(path)

run = subprocess.run([executable], cwd=project, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
if run.stdout:
    sys.stdout.buffer.write(run.stdout)
if run.stderr:
    sys.stderr.buffer.write(run.stderr)
assert run.returncode == 0, f"compiled restoration program exited with status {run.returncode}"

expected_files = {
    os.path.join(restore_dir, safe_one): prefix + suffix,
    os.path.join(restore_dir, safe_two): second_file,
}
for path, expected in expected_files.items():
    assert os.path.isfile(path), f"dynamic restored file {path} does not exist"
    with open(path, "rb") as f:
        actual = f.read()
    assert actual == expected, f"dynamic restored file {path} has incorrect binary contents"

assert os.path.isfile(rejected_path), "rejected.log was not produced for the dynamic manifest"
with open(rejected_path, "r", encoding="utf-8") as f:
    rejected = [line.rstrip("\r\n") for line in f if line.rstrip("\r\n")]
assert collections.Counter(rejected) == collections.Counter(malicious), \
    f"dynamic rejected.log mismatch: expected {malicious!r}, got {rejected!r}"

for path in escaped_paths:
    assert not os.path.lexists(path), f"malicious dynamic target was written outside restore directory: {path}"
PY_EOF
}

if verify_all; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
