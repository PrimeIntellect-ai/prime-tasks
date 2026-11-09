#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import struct
import subprocess
import tempfile
import uuid
import pytest

SCRIPT_PATH = "/home/user/pka_guard.py"
CLEAN_CORPUS_DIR = "/app/corpora/clean"
EVIL_CORPUS_DIR = "/app/corpora/evil"


def run_guard(path, cwd=None, extra_args=None):
    args = ["python3", SCRIPT_PATH, path]
    if extra_args:
        args.extend(extra_args)
    return subprocess.run(args, cwd=cwd, capture_output=True, timeout=10)


def write_pka(path, entries):
    with open(path, "wb") as f:
        f.write(b"PKA\x01")
        f.write(struct.pack("<I", len(entries)))
        for entry_path, entry_type, data in entries:
            path_bytes = entry_path.encode("utf-8")
            data_bytes = data.encode("utf-8") if isinstance(data, str) else data
            f.write(struct.pack("<H", len(path_bytes)))
            f.write(path_bytes)
            f.write(struct.pack("<B", entry_type))
            f.write(struct.pack("<I", len(data_bytes)))
            f.write(data_bytes)


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Gatekeeper script not found at {SCRIPT_PATH}"
    # Preserve the original invocation check: the script is run through Python below.


def test_clean_corpus():
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Missing clean corpus directory: {CLEAN_CORPUS_DIR}"

    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith('.pka')]
    assert len(clean_files) > 0, "No .pka files found in clean corpus"

    rejected_files = []
    for pka_file in clean_files:
        result = run_guard(pka_file)
        if result.returncode != 0:
            rejected_files.append(os.path.basename(pka_file))

    if rejected_files:
        pytest.fail(f"{len(rejected_files)} of {len(clean_files)} clean rejected: {', '.join(rejected_files)}")


def test_evil_corpus():
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Missing evil corpus directory: {EVIL_CORPUS_DIR}"

    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith('.pka')]
    assert len(evil_files) > 0, "No .pka files found in evil corpus"

    bypassed_files = []
    for pka_file in evil_files:
        result = run_guard(pka_file)
        if result.returncode == 0:
            bypassed_files.append(os.path.basename(pka_file))

    if bypassed_files:
        pytest.fail(f"{len(bypassed_files)} of {len(evil_files)} evil bypassed: {', '.join(bypassed_files)}")


def test_generated_archives_on_unlabelled_novel_paths():
    token = uuid.uuid4().hex
    with tempfile.TemporaryDirectory(prefix=f"pka-check-{token}-") as workdir:
        outside = os.path.join("/tmp", f"pka-out-{uuid.uuid4().hex}")
        cases = [
            # Safe archives, including harmless normalization and symlink traversal
            # which remains within the extraction root.
            (True, []),
            (True, [("plain.txt", 0, b"payload")]),
            (True, [("alpha/../beta.txt", 0, b"payload")]),
            (True, [("nested/deep/link", 2, "../../inside.txt")]),
            (True, [("d", 1, b""), ("d/file", 0, b"x"), ("d/link", 2, "file")]),
            # Unsafe entry paths of every extractable kind.
            (False, [(outside, 0, b"x")]),
            (False, [("../escape.txt", 0, b"x")]),
            (False, [("one/../../escape.txt", 1, b"")]),
            (False, [("../../escape-link", 2, "inside")]),
            # Unsafe symlink targets, resolved relative to the link's parent.
            (False, [("link", 2, outside)]),
            (False, [("link", 2, "../escape")]),
            (False, [("nested/deep/link", 2, "../../../escape")]),
        ]

        for should_accept, entries in cases:
            archive = os.path.join(workdir, f"{uuid.uuid4().hex}.pka")
            write_pka(archive, entries)
            result = run_guard(archive, cwd=workdir)
            if should_accept:
                assert result.returncode == 0, f"safe generated archive was rejected: {result.stderr!r}"
            else:
                assert result.returncode != 0, "unsafe generated archive was accepted"


def test_malformed_archives_are_rejected():
    malformed = [
        b"",
        b"NOTP" + struct.pack("<I", 0),
        b"PKA\x01",
        b"PKA\x01" + struct.pack("<I", 1),
        b"PKA\x01" + struct.pack("<I", 1) + struct.pack("<H", 10) + b"abc",
        b"PKA\x01" + struct.pack("<I", 1) + struct.pack("<H", 1) + b"x" + b"\x00",
        b"PKA\x01" + struct.pack("<I", 1) + struct.pack("<H", 1) + b"x" + b"\x00" + struct.pack("<I", 100) + b"short",
    ]

    with tempfile.TemporaryDirectory(prefix=f"pka-format-{uuid.uuid4().hex}-") as workdir:
        for blob in malformed:
            archive = os.path.join(workdir, f"{uuid.uuid4().hex}.pka")
            with open(archive, "wb") as f:
                f.write(blob)
            assert run_guard(archive, cwd=workdir).returncode != 0, "malformed archive was accepted"


def test_requires_exactly_one_archive_argument():
    no_args = subprocess.run(["python3", SCRIPT_PATH], capture_output=True, timeout=10)
    assert no_args.returncode != 0

    with tempfile.TemporaryDirectory(prefix=f"pka-args-{uuid.uuid4().hex}-") as workdir:
        archive = os.path.join(workdir, f"{uuid.uuid4().hex}.pka")
        write_pka(archive, [])
        extra = subprocess.run(
            ["python3", SCRIPT_PATH, archive, "unexpected"],
            cwd=workdir,
            capture_output=True,
            timeout=10,
        )
        assert extra.returncode != 0
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
