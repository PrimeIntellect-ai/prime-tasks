#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import gzip
import io
import os
import random
import secrets
import stat
import subprocess
import tarfile
import tempfile
import zipfile

import pytest

BINARY = "/home/user/artifact_filter"
SOURCE = "/home/user/artifact_filter.go"
PREFIX = "OMEGA_BUILD_v7"


def run_filter(binary, archive):
    try:
        return subprocess.run(
            [binary, archive], capture_output=True, timeout=8
        ).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"Filter timed out on {archive}")


def test_artifact_filter_exists():
    binary_path = "/home/user/artifact_filter"
    assert os.path.isfile(binary_path), f"Compiled binary not found at {binary_path}"
    assert os.access(binary_path, os.X_OK), f"Binary at {binary_path} is not executable"


def test_artifact_filter_clean_corpus():
    binary_path = "/home/user/artifact_filter"
    if not os.path.exists(binary_path):
        pytest.fail("Binary /home/user/artifact_filter does not exist.")

    clean_dir = "/app/corpora/clean"
    clean_files = glob.glob(os.path.join(clean_dir, "*"))

    assert len(clean_files) > 0, "No files found in clean corpus"

    failed_files = []
    for filepath in clean_files:
        if not os.path.isfile(filepath):
            continue
        result = subprocess.run([binary_path, filepath], capture_output=True)
        if result.returncode != 0:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean modified/rejected: {', '.join(failed_files)}")


def test_artifact_filter_evil_corpus():
    binary_path = "/home/user/artifact_filter"
    if not os.path.exists(binary_path):
        pytest.fail("Binary /home/user/artifact_filter does not exist.")

    evil_dir = "/app/corpora/evil"
    evil_files = glob.glob(os.path.join(evil_dir, "*"))

    assert len(evil_files) > 0, "No files found in evil corpus"

    failed_files = []
    for filepath in evil_files:
        if not os.path.isfile(filepath):
            continue
        result = subprocess.run([binary_path, filepath], capture_output=True)
        if result.returncode == 0:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil bypassed: {', '.join(failed_files)}")


@pytest.fixture(scope="session")
def rebuilt_binary():
    assert os.path.isfile(SOURCE), f"Go source not found at {SOURCE}"
    assert not os.path.islink(SOURCE), "Go source must be a regular submitted file"
    assert not os.path.islink(BINARY), "Compiled binary must not be a symlink"

    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "artifact_filter is not a compiled ELF binary"

    metadata = subprocess.run(
        ["go", "version", "-m", BINARY], capture_output=True, text=True
    )
    assert metadata.returncode == 0, "artifact_filter is not a Go binary"

    output = os.path.join(tempfile.mkdtemp(prefix="rebuilt-filter-"), "artifact_filter")
    env = os.environ.copy()
    env["GO111MODULE"] = "off"
    built = subprocess.run(
        ["go", "build", "-o", output, SOURCE],
        capture_output=True,
        text=True,
        env=env,
        timeout=60,
    )
    assert built.returncode == 0, f"Could not compile artifact_filter.go: {built.stderr}"
    assert os.path.isfile(output) and os.access(output, os.X_OK)
    return output


def add_tar_dir(t, name):
    info = tarfile.TarInfo(name.rstrip("/") + "/")
    info.type = tarfile.DIRTYPE
    info.mode = 0o755
    t.addfile(info)


def add_tar_file(t, name, data):
    info = tarfile.TarInfo(name)
    info.mode = 0o644
    info.size = len(data)
    t.addfile(info, io.BytesIO(data))


def make_tar(path, entries):
    with tarfile.open(path, "w:gz") as t:
        for kind, name, value in entries:
            if kind == "dir":
                add_tar_dir(t, name)
            elif kind == "file":
                add_tar_file(t, name, value)
            elif kind == "symlink":
                info = tarfile.TarInfo(name)
                info.type = tarfile.SYMTYPE
                info.mode = 0o777
                info.linkname = value
                t.addfile(info)


def zip_symlink(z, name, target):
    info = zipfile.ZipInfo(name)
    info.create_system = 3
    info.external_attr = (stat.S_IFLNK | 0o777) << 16
    z.writestr(info, target)


def random_path(root, suffix):
    return os.path.join(root, secrets.token_hex(16) + suffix)


def make_runtime_cases():
    root = tempfile.mkdtemp(prefix="archive-validation-")
    payload = secrets.token_bytes(31)
    cases = []

    p = random_path(root, ".zip")
    with zipfile.ZipFile(p, "w", compression=zipfile.ZIP_DEFLATED) as z:
        z.writestr(PREFIX + "/", b"")
        z.writestr(PREFIX + "/nested/", b"")
        z.writestr(PREFIX + "/nested/" + secrets.token_hex(5) + ".bin", payload)
    cases.append((p, 0))

    p = random_path(root, ".tar.gz")
    make_tar(p, [
        ("dir", PREFIX, None),
        ("dir", PREFIX + "/data", None),
        ("file", PREFIX + "/data/" + secrets.token_hex(5), payload),
    ])
    cases.append((p, 0))

    p = random_path(root, ".zip")
    with zipfile.ZipFile(p, "w") as z:
        z.writestr(PREFIX + "/data/file", payload)
        zip_symlink(z, PREFIX + "/link", "data/file")
    cases.append((p, 0))

    p = random_path(root, ".tar.gz")
    make_tar(p, [
        ("dir", PREFIX, None),
        ("file", PREFIX + "/target", payload),
        ("symlink", PREFIX + "/safe-link", "target"),
    ])
    cases.append((p, 0))

    p = random_path(root, ".zip")
    with zipfile.ZipFile(p, "w") as z:
        z.writestr(PREFIX + "/../../" + secrets.token_hex(6), payload)
    cases.append((p, 1))

    p = random_path(root, ".tar.gz")
    make_tar(p, [("file", "/tmp/" + secrets.token_hex(6), payload)])
    cases.append((p, 1))

    p = random_path(root, ".zip")
    with zipfile.ZipFile(p, "w") as z:
        z.writestr("NOT_" + secrets.token_hex(6) + "/file", payload)
    cases.append((p, 1))

    p = random_path(root, ".tar.gz")
    make_tar(p, [("file", secrets.token_hex(8) + ".txt", payload)])
    cases.append((p, 1))

    p = random_path(root, ".zip")
    with zipfile.ZipFile(p, "w") as z:
        z.writestr(PREFIX + "/target", payload)
        zip_symlink(z, PREFIX + "/escape", "../../" + secrets.token_hex(6))
    cases.append((p, 1))

    p = random_path(root, ".tar.gz")
    make_tar(p, [
        ("file", PREFIX + "/target", payload),
        ("symlink", PREFIX + "/escape", "/etc/" + secrets.token_hex(6)),
    ])
    cases.append((p, 1))

    p = random_path(root, ".zip")
    with open(p, "wb") as f:
        f.write(secrets.token_bytes(73))
    cases.append((p, 1))

    p = random_path(root, ".tar.gz")
    with open(p, "wb") as f:
        f.write(gzip.compress(secrets.token_bytes(37))[:-4])
    cases.append((p, 1))

    p = random_path(root, ".tar.gz")
    make_tar(p, [("file", PREFIX + "/../OTHER/file", payload)])
    cases.append((p, 1))

    random.SystemRandom().shuffle(cases)
    return cases


def test_runtime_generated_archives(rebuilt_binary):
    cases = make_runtime_cases()
    for binary in (BINARY, rebuilt_binary):
        ordered = list(cases)
        random.SystemRandom().shuffle(ordered)
        for archive, expected in ordered:
            actual = run_filter(binary, archive)
            assert actual == expected, (
                f"{binary} returned {actual}, expected {expected}, "
                f"for generated archive {archive}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
