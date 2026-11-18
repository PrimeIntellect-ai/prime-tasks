#!/bin/bash
set +e
mkdir -p /logs/verifier

cat <<'PY' > /tmp/verify_safe_extractor.py
import hashlib
import io
import os
import secrets
import shutil
import stat
import subprocess
import tarfile

HOME = "/home/user"
SOURCE = f"{HOME}/safe_extractor.cpp"
BINARY = f"{HOME}/safe_extractor"
INPUT = f"{HOME}/input.tar"
EXTRACTED = f"{HOME}/extracted"
MANIFEST = f"{HOME}/manifest.txt"


def require_regular(path):
    st = os.lstat(path)
    assert stat.S_ISREG(st.st_mode), f"{path} is not a regular file"
    return st


def add_bytes(archive, name, content):
    info = tarfile.TarInfo(name)
    info.size = len(content)
    info.mode = 0o644
    archive.addfile(info, io.BytesIO(content))


def create_case(dynamic=False):
    if dynamic:
        token = secrets.token_hex(6)
        safe_files = {
            f"safe_{token}.bin": secrets.token_bytes(47),
            f"docs_{token}/safe.bin": secrets.token_bytes(59),
            f"data_{token}/nested.bin": secrets.token_bytes(71),
        }
        nested_name = f"bundle_{token}.tar"
        nested_safe_path = f"data_{token}/nested.bin"
        abs_target = f"/tmp/absolute_attack_{token}.txt"
        traversal_name = f"folder/../../traversal_attack_{token}.txt"
        traversal_target = f"{HOME}/traversal_attack_{token}.txt"
        nested_bad_name = f"../nested_attack_{token}.txt"
        nested_bad_target = f"{HOME}/nested_attack_{token}.txt"
    else:
        safe_files = {
            "safe1.txt": b"Safe content 1\n",
            "docs/safe2.txt": b"Safe content 2\n",
            "data/nested_safe.txt": b"Nested safe\n",
        }
        nested_name = "nested.tar"
        nested_safe_path = "data/nested_safe.txt"
        abs_target = "/etc/hacked.txt"
        traversal_name = "docs/../../hacked2.txt"
        traversal_target = f"{HOME}/hacked2.txt"
        nested_bad_name = "../nested_malicious.txt"
        nested_bad_target = f"{HOME}/nested_malicious.txt"

    malicious = b"Malicious!\n" + secrets.token_bytes(23)
    nested_buffer = io.BytesIO()
    with tarfile.open(fileobj=nested_buffer, mode="w") as nested:
        add_bytes(nested, nested_safe_path, safe_files[nested_safe_path])
        add_bytes(nested, nested_bad_name, malicious)

    with tarfile.open(INPUT, mode="w") as outer:
        for path, content in safe_files.items():
            if path != nested_safe_path:
                add_bytes(outer, path, content)
        add_bytes(outer, nested_name, nested_buffer.getvalue())
        add_bytes(outer, abs_target, malicious)
        add_bytes(outer, traversal_name, malicious)

    attack_targets = {
        abs_target,
        traversal_target,
        nested_bad_target,
        # Preserve the original verifier's traversal assertion as well.
        "/home/hacked2.txt",
    }
    return safe_files, attack_targets


def clean_state(attack_targets):
    if os.path.lexists(EXTRACTED):
        if os.path.isdir(EXTRACTED) and not os.path.islink(EXTRACTED):
            shutil.rmtree(EXTRACTED)
        else:
            os.unlink(EXTRACTED)
    os.makedirs(EXTRACTED)
    if os.path.lexists(MANIFEST):
        os.unlink(MANIFEST)
    for path in attack_targets:
        if os.path.lexists(path):
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.unlink(path)


def validate(safe_files, attack_targets):
    # Original malicious-path assertions, plus dynamically generated targets.
    for path in attack_targets:
        assert not os.path.exists(path), f"Path traversal target was extracted: {path}"

    expected_lines = []
    for relative_path, expected_content in safe_files.items():
        output_path = os.path.join(EXTRACTED, relative_path)
        require_regular(output_path)
        with open(output_path, "rb") as f:
            actual_content = f.read()
        assert actual_content == expected_content, (
            f"Extracted content is incorrect for {relative_path}"
        )
        expected_lines.append(
            f"{hashlib.sha256(expected_content).hexdigest()}  {relative_path}"
        )

    expected_lines.sort(key=lambda line: line.split("  ", 1)[1])
    require_regular(MANIFEST)
    with open(MANIFEST, "r", encoding="utf-8") as f:
        actual_lines = f.read().splitlines()
    assert actual_lines == expected_lines, (
        "Manifest contents are incorrect.\nExpected:\n"
        + "\n".join(expected_lines)
        + "\nActual:\n"
        + "\n".join(actual_lines)
    )

    # Preserve the original malicious-content check.
    for root, _, files in os.walk(EXTRACTED):
        for filename in files:
            path = os.path.join(root, filename)
            if path.endswith(".tar"):
                continue
            with open(path, "rb") as f:
                assert b"Malicious!" not in f.read(), f"Malicious content found in {path}"


def run_case(dynamic=False):
    safe_files, attack_targets = create_case(dynamic)
    clean_state(attack_targets)
    result = subprocess.run(
        [BINARY], cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=30, check=False
    )
    assert result.returncode == 0, (
        f"safe_extractor exited with {result.returncode}.\n"
        f"stdout:\n{result.stdout.decode(errors='replace')}\n"
        f"stderr:\n{result.stderr.decode(errors='replace')}"
    )
    validate(safe_files, attack_targets)


source_stat = require_regular(SOURCE)
assert source_stat.st_size > 0, "safe_extractor.cpp is empty"
binary_stat = require_regular(BINARY)
assert binary_stat.st_mode & 0o111, "safe_extractor is not executable"
with open(BINARY, "rb") as f:
    assert f.read(4) == b"\x7fELF", "safe_extractor is not a compiled ELF executable"

# First retain all assertions against the archive from the original setup.
run_case(dynamic=False)
# Then exercise the submitted tool on verifier-generated names and contents.
run_case(dynamic=True)
PY

if python3 /tmp/verify_safe_extractor.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
