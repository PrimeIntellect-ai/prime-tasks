#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import random
import stat
import subprocess
import tarfile
import tempfile
import uuid
from pathlib import Path

import pytest

EXECUTABLE = "/home/user/artifact_filter"
SOURCE = "/home/user/artifact_filter.c"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"
MAGIC = "APPROVED_ARTIFACT_v7_XYZ"


def run_filter(executable, *args):
    try:
        return subprocess.run(
            [executable, *map(str, args)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=8,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"{executable} timed out on arguments {args}")


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} does not exist. Did you compile your C program?"
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
    assert not os.path.islink(EXECUTABLE), f"{EXECUTABLE} must be a compiled program, not a symlink."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXECUTABLE} is not an ELF executable."


def test_c_source_exists_and_compiles(tmp_path):
    assert os.path.isfile(SOURCE), f"Required C source {SOURCE} does not exist."
    assert not os.path.islink(SOURCE), f"{SOURCE} must be a regular C source file, not a symlink."
    rebuilt = tmp_path / "rebuilt_artifact_filter"
    result = subprocess.run(
        ["gcc", "-std=c11", "-O2", "-Wall", "-Wextra", SOURCE, "-o", str(rebuilt)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, "artifact_filter.c did not compile:\n" + result.stderr.decode(errors="replace")
    assert rebuilt.read_bytes()[:4] == b"\x7fELF"


def test_clean_corpus_accepted():
    if not os.path.isfile(EXECUTABLE):
        pytest.skip("Executable missing")

    clean_bundles = [os.path.join(CLEAN_CORPUS_DIR, d) for d in os.listdir(CLEAN_CORPUS_DIR)
                     if os.path.isdir(os.path.join(CLEAN_CORPUS_DIR, d))]

    assert len(clean_bundles) > 0, "No clean bundles found in the corpus."

    failed_clean = []
    for bundle in clean_bundles:
        result = run_filter(EXECUTABLE, bundle)
        if result.returncode != 0:
            failed_clean.append((os.path.basename(bundle), result.returncode))

    if failed_clean:
        details = ", ".join([f"{name} (exit code {code})" for name, code in failed_clean])
        pytest.fail(f"{len(failed_clean)} of {len(clean_bundles)} clean bundles were incorrectly rejected: {details}")


def test_evil_corpus_rejected():
    if not os.path.isfile(EXECUTABLE):
        pytest.skip("Executable missing")

    evil_bundles = [os.path.join(EVIL_CORPUS_DIR, d) for d in os.listdir(EVIL_CORPUS_DIR)
                    if os.path.isdir(os.path.join(EVIL_CORPUS_DIR, d))]

    assert len(evil_bundles) > 0, "No evil bundles found in the corpus."

    failed_evil = []
    for bundle in evil_bundles:
        result = run_filter(EXECUTABLE, bundle)
        if result.returncode == 0:
            failed_evil.append(os.path.basename(bundle))

    if failed_evil:
        details = ", ".join(failed_evil)
        pytest.fail(f"{len(failed_evil)} of {len(evil_bundles)} evil bundles bypassed the filter (returned 0): {details}")


def opaque_name():
    return uuid.uuid4().hex


def write_manifest(path, text, mtime, malformed=False):
    data = text.encode("utf-16le")
    if malformed:
        data += b"\x00"
    path.write_bytes(data)
    os.utime(path, (mtime, mtime))


def write_archive(path, valid=True):
    if valid:
        with tarfile.open(path, "w:gz") as tf:
            payload = os.urandom(47)
            info = tarfile.TarInfo(opaque_name())
            info.size = len(payload)
            tf.addfile(info, io.BytesIO(payload))
    else:
        path.write_bytes(b"\x1f\x8b\x08corrupt-" + os.urandom(29))


def new_bundle(root):
    path = root / opaque_name()
    path.mkdir()
    return path


def standard_bundle(root, active_text=f"prefix {MAGIC} suffix"):
    bundle = new_bundle(root)
    write_manifest(bundle / (opaque_name() + ".txt"), "older text without integrity token", 1600000000)
    write_manifest(bundle / (opaque_name() + ".txt"), active_text, 1700000000)
    write_archive(bundle / (opaque_name() + ".tar.gz"))
    return bundle


def build_generated_cases(root):
    cases = []

    basic = standard_bundle(root)
    cases.append((basic, 0, "valid generated bundle"))

    internal = standard_bundle(root)
    nested = internal / opaque_name()
    nested.mkdir()
    manifest = next(internal.glob("*.txt"))
    os.symlink(os.path.relpath(manifest, nested), nested / opaque_name())
    cases.append((internal, 0, "valid contained symlink"))

    no_magic = standard_bundle(root, "ordinary manifest text")
    cases.append((no_magic, 1, "missing magic string"))

    wrong_newest = new_bundle(root)
    write_manifest(wrong_newest / (opaque_name() + ".txt"), MAGIC, 1600000000)
    write_manifest(wrong_newest / (opaque_name() + ".txt"), "new manifest without token", 1700000000)
    write_archive(wrong_newest / (opaque_name() + ".tar.gz"))
    cases.append((wrong_newest, 1, "magic appears only in an older manifest"))

    malformed = new_bundle(root)
    write_manifest(malformed / (opaque_name() + ".txt"), MAGIC, 1700000000, malformed=True)
    write_archive(malformed / (opaque_name() + ".tar.gz"))
    cases.append((malformed, 1, "malformed UTF-16LE manifest"))

    bad_archive = standard_bundle(root)
    next(bad_archive.glob("*.tar.gz")).unlink()
    write_archive(bad_archive / (opaque_name() + ".tar.gz"), valid=False)
    cases.append((bad_archive, 1, "corrupt archive"))

    outside = standard_bundle(root)
    outside_target = root / opaque_name()
    outside_target.write_text("outside")
    os.symlink(outside_target, outside / opaque_name())
    cases.append((outside, 1, "absolute external symlink"))

    traversal = standard_bundle(root)
    sibling = root / opaque_name()
    sibling.write_text("outside")
    subdir = traversal / opaque_name()
    subdir.mkdir()
    os.symlink(os.path.relpath(sibling, subdir), subdir / opaque_name())
    cases.append((traversal, 1, "nested traversal symlink"))

    missing_manifest = new_bundle(root)
    write_archive(missing_manifest / (opaque_name() + ".tar.gz"))
    cases.append((missing_manifest, 1, "missing manifest"))

    missing_archive = new_bundle(root)
    write_manifest(missing_archive / (opaque_name() + ".txt"), MAGIC, 1700000000)
    cases.append((missing_archive, 1, "missing archive"))

    multiple_archives = standard_bundle(root)
    write_archive(multiple_archives / (opaque_name() + ".tar.gz"))
    cases.append((multiple_archives, 1, "more than one archive"))

    random.SystemRandom().shuffle(cases)
    return cases


@pytest.fixture(scope="module")
def tested_executables():
    assert os.path.isfile(EXECUTABLE) and os.access(EXECUTABLE, os.X_OK)
    assert os.path.isfile(SOURCE) and not os.path.islink(SOURCE)
    build_dir = Path(tempfile.mkdtemp(prefix="af-build-"))
    rebuilt = build_dir / opaque_name()
    result = subprocess.run(
        ["gcc", "-std=c11", "-O2", SOURCE, "-o", str(rebuilt)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, "artifact_filter.c did not compile:\n" + result.stderr.decode(errors="replace")
    return [EXECUTABLE, str(rebuilt)]


def test_generated_hidden_bundles(tested_executables, tmp_path):
    root = tmp_path / opaque_name()
    root.mkdir()
    cases = build_generated_cases(root)
    for executable in tested_executables:
        for bundle, expected, description in cases:
            result = run_filter(executable, bundle)
            assert result.returncode == expected, (
                f"{executable} returned {result.returncode}, expected {expected}, for {description}"
            )


def test_exactly_one_argument(tested_executables, tmp_path):
    bundle = standard_bundle(tmp_path)
    for executable in tested_executables:
        assert run_filter(executable).returncode == 1, f"{executable} must reject a missing argument with status 1"
        assert run_filter(executable, bundle, bundle).returncode == 1, f"{executable} must reject extra arguments with status 1"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
