#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import io
import json
import os
import random
import subprocess
import tarfile
import tempfile
import uuid
from pathlib import Path

import pytest

SCRIPT_PATH = "/home/user/verify_backup.sh"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"


def run_script(archive, cwd=None):
    return subprocess.run(
        [SCRIPT_PATH, str(archive)],
        cwd=cwd,
        capture_output=True,
        timeout=15,
    )


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_clean_corpus():
    clean_tars = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.tar"))
    assert len(clean_tars) > 0, "No clean tarballs found."

    failed_files = []
    for tar in clean_tars:
        result = run_script(tar)
        if result.returncode != 0:
            failed_files.append(os.path.basename(tar))

    if failed_files:
        pytest.fail(
            f"{len(failed_files)} of {len(clean_tars)} clean modified/rejected: "
            + ", ".join(failed_files)
        )


def test_evil_corpus():
    evil_tars = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.tar"))
    assert len(evil_tars) > 0, "No evil tarballs found."

    bypassed_files = []
    for tar in evil_tars:
        result = run_script(tar)
        if result.returncode != 1:
            bypassed_files.append(os.path.basename(tar))

    if bypassed_files:
        pytest.fail(
            f"{len(bypassed_files)} of {len(evil_tars)} evil bypassed: "
            + ", ".join(bypassed_files)
        )


def add_bytes(tar, name, data=b""):
    info = tarfile.TarInfo(name)
    info.size = len(data)
    tar.addfile(info, io.BytesIO(data))


def make_archive(path, members):
    with tarfile.open(path, "w") as tar:
        for member in members:
            kind = member[0]
            if kind == "file":
                add_bytes(tar, member[1], member[2])
            elif kind == "dir":
                info = tarfile.TarInfo(member[1])
                info.type = tarfile.DIRTYPE
                tar.addfile(info)
            elif kind == "symlink":
                info = tarfile.TarInfo(member[1])
                info.type = tarfile.SYMTYPE
                info.linkname = member[2]
                tar.addfile(info)
            else:
                raise AssertionError(f"Unknown member type: {kind}")


def config(mount_path):
    return json.dumps({"mount_path": mount_path}).encode()


def test_generated_archives_and_no_extraction_side_effects():
    # Every archive has an opaque randomized pathname in one common directory, so
    # its expected result cannot be inferred from clean/evil path components.
    with tempfile.TemporaryDirectory(prefix="backup-verifier-") as temp:
        base = Path(temp)
        archives = base / ("inputs-" + uuid.uuid4().hex)
        archives.mkdir()

        absolute_escape = Path("/tmp") / ("verify-backup-absolute-" + uuid.uuid4().hex)
        traversal_escape = Path("/tmp") / ("verify-backup-traversal-" + uuid.uuid4().hex)
        for target in (absolute_escape, traversal_escape):
            assert not target.exists()

        cases = [
            (0, [
                ("file", "app_config.json", config("/srv/application")),
                ("file", "docs/readme.txt", b"safe"),
                ("symlink", "latest-readme", "docs/readme.txt"),
            ]),
            (0, [("file", "app_config.json", config("/media/usb_backup2"))]),
            (0, [("file", "nested/app_config.json", config("/media/usb_backup/private"))]),
            (0, [("file", "name..with-dots.txt", b"safe")]),
            (1, [("file", str(absolute_escape), b"must not be extracted")]),
            (1, [("symlink", "ordinary-name", "/etc/passwd")]),
            (1, [("file", "app_config.json", config("/media/usb_backup"))]),
            (1, [("file", "app_config.json", config("/media/usb_backup/snapshots/one"))]),
        ]

        prepared = []
        for expected, members in cases:
            archive = archives / (uuid.uuid4().hex + ".tar")
            make_archive(archive, members)
            prepared.append((archive, expected))

        # Construct traversal relative to the exact working directory used for
        # this invocation, allowing detection of an unsafe extraction attempt.
        traversal_cwd = base / ("run-" + uuid.uuid4().hex) / "a" / "b"
        traversal_cwd.mkdir(parents=True)
        traversal_name = os.path.relpath(traversal_escape, traversal_cwd)
        assert traversal_name.startswith(".." + os.sep)
        traversal_archive = archives / (uuid.uuid4().hex + ".tar")
        make_archive(
            traversal_archive,
            [("file", traversal_name, b"must not be extracted")],
        )
        prepared.append((traversal_archive, 1))

        random.SystemRandom().shuffle(prepared)
        failures = []
        for archive, expected in prepared:
            if archive == traversal_archive:
                cwd = traversal_cwd
            else:
                cwd = base / ("run-" + uuid.uuid4().hex)
                cwd.mkdir()

            before = set(cwd.rglob("*"))
            result = run_script(archive, cwd=cwd)
            after = set(cwd.rglob("*"))
            if result.returncode != expected:
                failures.append(
                    f"{archive.name}: expected {expected}, got {result.returncode}"
                )
            assert after == before, (
                f"{archive.name} left extraction artifacts in its working directory"
            )
            assert not absolute_escape.exists(), "Absolute-path member was extracted"
            assert not traversal_escape.exists(), "Traversal member escaped the working directory"

        if failures:
            pytest.fail("Generated archive failures: " + "; ".join(failures))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
