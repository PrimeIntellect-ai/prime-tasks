#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import io
import os
import random
import secrets
import subprocess
import tarfile
import tempfile

import pytest

SCRIPT_PATH = "/home/user/filter_artifacts.sh"
CLEAN_DIR = "/app/corpora/clean"
EVIL_DIR = "/app/corpora/evil"
BANNED_CODE = "VANGUARD-7"


def run_filter(path_args):
    try:
        return subprocess.run(
            ["bash", SCRIPT_PATH, *path_args],
            capture_output=True,
            timeout=20,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Filter timed out for arguments: {path_args!r}")


def add_regular(tar, name, data):
    info = tarfile.TarInfo(name)
    info.size = len(data)
    info.mode = 0o644
    info.mtime = 1700000000
    tar.addfile(info, io.BytesIO(data))


def add_symlink(tar, name, target):
    info = tarfile.TarInfo(name)
    info.type = tarfile.SYMTYPE
    info.linkname = target
    info.mode = 0o777
    info.mtime = 1700000000
    tar.addfile(info)


def manifest_for(payloads):
    lines = []
    for name, data in payloads.items():
        lines.append(f"{hashlib.sha256(data).hexdigest()}  {name}\n")
    return "".join(lines).encode("ascii")


def base_members(metadata_text=None):
    token = secrets.token_hex(6)
    payloads = {
        f"payload-{token}.bin": secrets.token_bytes(73),
        f"dir with space/file {token}.txt": secrets.token_bytes(41),
    }
    metadata_text = metadata_text or f"プロジェクト-アポロ-{token}"
    members = [("file", name, data) for name, data in payloads.items()]
    members.extend([
        ("file", "metadata.txt", metadata_text.encode("shift_jis")),
        ("file", "manifest.sha256", manifest_for(payloads)),
    ])
    return members, payloads


def write_archive(path, members):
    with tarfile.open(path, "w:gz") as tar:
        for kind, name, value in members:
            if kind == "file":
                add_regular(tar, name, value)
            elif kind == "symlink":
                add_symlink(tar, name, value)
            else:
                raise AssertionError(f"Unknown member kind: {kind}")


def build_generated_cases():
    root = tempfile.mkdtemp(prefix="artifact_validation_")
    specs = []

    # Several ordinary compliant archives with randomized payloads and names.
    for _ in range(3):
        members, _ = base_members()
        specs.append((members, 0))

    # A compliant archive containing a symlink that remains inside extraction.
    token = secrets.token_hex(6)
    payload = secrets.token_bytes(89)
    payloads = {f"payload-{token}.bin": payload, f"alias-{token}.bin": payload}
    members = [
        ("file", f"payload-{token}.bin", payload),
        ("symlink", f"alias-{token}.bin", f"payload-{token}.bin"),
        ("file", "metadata.txt", "安全なプロジェクト".encode("shift_jis")),
        ("file", "manifest.sha256", manifest_for(payloads)),
    ]
    specs.append((members, 0))

    # Correctly formed archive whose metadata contains the intercepted code.
    members, _ = base_members(f"秘密契約 {BANNED_CODE} 終了")
    specs.append((members, 1))

    # Incorrect checksum.
    members, payloads = base_members()
    bad_manifest = manifest_for(payloads).decode("ascii").splitlines()
    bad_manifest[0] = "0" * 64 + bad_manifest[0][64:]
    members = [m for m in members if m[1] != "manifest.sha256"]
    members.append(("file", "manifest.sha256", ("\n".join(bad_manifest) + "\n").encode("ascii")))
    specs.append((members, 1))

    # Manifest references a nonexistent payload.
    members, payloads = base_members()
    missing_manifest = manifest_for(payloads) + (hashlib.sha256(b"missing").hexdigest() + "  absent/file.bin\n").encode("ascii")
    members = [m for m in members if m[1] != "manifest.sha256"]
    members.append(("file", "manifest.sha256", missing_manifest))
    specs.append((members, 1))

    # Required metadata and manifest files are independently absent.
    members, _ = base_members()
    specs.append(([m for m in members if m[1] != "metadata.txt"], 1))
    members, _ = base_members()
    specs.append(([m for m in members if m[1] != "manifest.sha256"], 1))

    # Otherwise valid archives with traversal, absolute, and escaping symlink entries.
    members, _ = base_members()
    specs.append((members + [("file", f"nested/../../escape-{secrets.token_hex(5)}", b"escape")], 1))
    members, _ = base_members()
    specs.append((members + [("file", f"/tmp/absolute-{secrets.token_hex(5)}", b"escape")], 1))
    members, _ = base_members()
    specs.append((members + [("symlink", f"link-{secrets.token_hex(5)}", "../../etc/passwd")], 1))

    # Randomize creation order so timestamps and inode order do not encode answers.
    random.SystemRandom().shuffle(specs)
    cases = []
    for members, expected in specs:
        path = os.path.join(root, f"{secrets.token_hex(16)}.tar.gz")
        write_archive(path, members)
        cases.append((path, expected))

    malformed = os.path.join(root, f"{secrets.token_hex(16)}.tar.gz")
    with open(malformed, "wb") as f:
        f.write(secrets.token_bytes(127))
    cases.append((malformed, 1))
    random.SystemRandom().shuffle(cases)
    return cases


GENERATED_CASES = build_generated_cases()


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"The script {SCRIPT_PATH} is not executable."


def test_clean_corpus():
    assert os.path.isdir(CLEAN_DIR), f"Clean corpus directory {CLEAN_DIR} is missing."
    clean_files = [f for f in os.listdir(CLEAN_DIR) if f.endswith('.tar.gz')]
    assert len(clean_files) > 0, f"No .tar.gz files found in {CLEAN_DIR}."

    failed_files = []
    for filename in clean_files:
        filepath = os.path.join(CLEAN_DIR, filename)
        result = run_filter([filepath])
        if result.returncode != 0:
            failed_files.append(filename)

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean modified/rejected. Offending files: {', '.join(failed_files)}")


def test_evil_corpus():
    assert os.path.isdir(EVIL_DIR), f"Evil corpus directory {EVIL_DIR} is missing."
    evil_files = [f for f in os.listdir(EVIL_DIR) if f.endswith('.tar.gz')]
    assert len(evil_files) > 0, f"No .tar.gz files found in {EVIL_DIR}."

    bypassed_files = []
    for filename in evil_files:
        filepath = os.path.join(EVIL_DIR, filename)
        result = run_filter([filepath])
        if result.returncode == 0:
            bypassed_files.append(filename)

    if bypassed_files:
        pytest.fail(f"{len(bypassed_files)} of {len(evil_files)} evil bypassed. Offending files: {', '.join(bypassed_files)}")


def test_randomized_neutral_path_archives():
    failures = []
    for path, expected in GENERATED_CASES:
        result = run_filter([path])
        if result.returncode != expected:
            failures.append(
                f"{os.path.basename(path)} expected {expected}, got {result.returncode}; "
                f"stderr={result.stderr[:300]!r}"
            )
    if failures:
        pytest.fail("Randomized artifact failures:\n" + "\n".join(failures))


def test_requires_exactly_one_argument():
    no_args = run_filter([])
    assert no_args.returncode == 1, f"No-argument invocation returned {no_args.returncode}, expected 1"

    sample = GENERATED_CASES[0][0]
    extra_args = run_filter([sample, sample])
    assert extra_args.returncode == 1, f"Two-argument invocation returned {extra_args.returncode}, expected 1"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
