#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_secure_extraction.py
import base64
import io
import json
import os
import pathlib
import secrets
import shutil
import subprocess
import tarfile
import zlib

# Preserve the original final-state assertions.
txt_path = "/home/user/extracted_files.txt"
assert os.path.isfile(txt_path), f"File does not exist: {txt_path}"
with open(txt_path, "r") as f:
    lines = [line.strip() for line in f.readlines() if line.strip()]
expected = [
    "/home/user/project/main.py",
    "/home/user/project/utils/helper.py",
]
assert lines == expected, f"Content of {txt_path} does not match expected output. Got: {lines}"

main_path = "/home/user/project/main.py"
helper_path = "/home/user/project/utils/helper.py"
assert os.path.isfile(main_path), f"File does not exist: {main_path}"
with open(main_path, "rb") as f:
    assert f.read() == b'print("Hello World")', f"Incorrect content in {main_path}"
assert os.path.isfile(helper_path), f"File does not exist: {helper_path}"
with open(helper_path, "rb") as f:
    assert f.read() == b"def help(): pass", f"Incorrect content in {helper_path}"

secret_leak_path = "/home/user/secret_leak.txt"
overwrite_path = "/home/user/data/overwrite.txt"
assert not os.path.exists(secret_leak_path), f"Malicious file was extracted: {secret_leak_path}"
assert not os.path.exists(overwrite_path), f"Malicious file was extracted: {overwrite_path}"

# Locate the Python extraction artifact, excluding the two Python files that
# came from the supplied archive.
excluded = {
    pathlib.Path(main_path).resolve(),
    pathlib.Path(helper_path).resolve(),
    pathlib.Path(__file__).resolve(),
}
candidates = []
for root in (pathlib.Path("/home/user"), pathlib.Path("/tmp"), pathlib.Path("/workspace")):
    if not root.exists():
        continue
    try:
        paths = root.rglob("*.py")
        for path in paths:
            try:
                resolved = path.resolve()
                if resolved not in excluded and path.is_file() and "__pycache__" not in path.parts:
                    candidates.append(path)
            except OSError:
                pass
    except OSError:
        pass

# Deduplicate candidates while preserving order.
unique_candidates = []
seen = set()
for candidate in candidates:
    key = str(candidate.resolve())
    if key not in seen:
        seen.add(key)
        unique_candidates.append(candidate)
candidates = unique_candidates
assert candidates, "No Python extraction script was found"

# Build a fresh, unpredictable backup so hardcoded final files cannot pass.
token = secrets.token_hex(8)
safe_members = {
    f"pkg_{token}/module.py": b"value = " + secrets.token_bytes(24),
    f"assets/{token}.bin": secrets.token_bytes(193),
}
traversal_target = pathlib.Path(f"/home/user/escape_{token}.txt")
prefix_escape_dir = pathlib.Path(f"/home/user/project_evil_{token}")
prefix_escape_target = prefix_escape_dir / "pwn.txt"
absolute_target = pathlib.Path(f"/tmp/absolute_escape_{token}.txt")
malicious_members = {
    f"../escape_{token}.txt": b"TRAVERSAL",
    f"../project_evil_{token}/pwn.txt": b"PREFIX_ESCAPE",
    str(absolute_target): b"ABSOLUTE_ESCAPE",
}

tar_buffer = io.BytesIO()
with tarfile.open(fileobj=tar_buffer, mode="w") as archive:
    for name, content in list(safe_members.items()) + list(malicious_members.items()):
        info = tarfile.TarInfo(name=name)
        info.size = len(content)
        archive.addfile(info, io.BytesIO(content))
tar_bytes = tar_buffer.getvalue()

# Use a different chunk boundary from the setup archive.
chunks = []
for offset in range(0, len(tar_bytes), 137):
    chunks.append(base64.b64encode(zlib.compress(tar_bytes[offset:offset + 137])).decode("ascii"))
dynamic_backup = json.dumps({"chunks": chunks}).encode("utf-8")

project = pathlib.Path("/home/user/project")
manifest = pathlib.Path("/home/user/extracted_files.txt")
backup = pathlib.Path("/home/user/data/backup.json")
expected_dynamic_paths = sorted(str(project / name) for name in safe_members)


def remove_path(path):
    path = pathlib.Path(path)
    if path.is_symlink() or path.is_file():
        path.unlink(missing_ok=True)
    elif path.is_dir():
        shutil.rmtree(path)


def reset_dynamic_state():
    backup.write_bytes(dynamic_backup)
    manifest.unlink(missing_ok=True)
    remove_path(main_path)
    remove_path(helper_path)
    for name in safe_members:
        remove_path(project / name)
    remove_path(traversal_target)
    remove_path(prefix_escape_dir)
    remove_path(absolute_target)
    project.mkdir(parents=True, exist_ok=True)


def dynamic_result_is_valid():
    if not manifest.is_file():
        return False
    with manifest.open("r") as f:
        actual_manifest = [line.strip() for line in f.readlines() if line.strip()]
    if actual_manifest != expected_dynamic_paths:
        return False
    for name, expected_content in safe_members.items():
        output = project / name
        if not output.is_file() or output.is_symlink() or output.read_bytes() != expected_content:
            return False
    if traversal_target.exists() or prefix_escape_target.exists() or absolute_target.exists():
        return False
    return True

passed = False
errors = []
for candidate in candidates:
    reset_dynamic_state()
    try:
        result = subprocess.run(
            ["python3", str(candidate)],
            cwd=str(candidate.parent),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
            check=False,
        )
        if result.returncode == 0 and dynamic_result_is_valid():
            passed = True
            break
        errors.append(f"{candidate}: exit {result.returncode}")
    except (OSError, subprocess.SubprocessError) as exc:
        errors.append(f"{candidate}: {exc}")

assert passed, "No Python extraction script securely processed the dynamic backup. " + "; ".join(errors)
TEST_EOF

if python3 /tmp/test_secure_extraction.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
