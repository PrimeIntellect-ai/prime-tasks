#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import random
import subprocess
import tarfile
import tempfile
import uuid

SCRIPT_PATH = "/home/user/filter.py"
TRIGGER = b"__OVERRIDE_DOC_ROOT_PRIVILEGE__"


def run_filter(archive_path):
    result = subprocess.run(
        ["python3", SCRIPT_PATH, os.path.abspath(archive_path)],
        capture_output=True,
        timeout=15,
    )
    return result.returncode


def add_file(tar, name, data=b""):
    info = tarfile.TarInfo(name=name)
    info.size = len(data)
    tar.addfile(info, io.BytesIO(data))


def add_dir(tar, name):
    info = tarfile.TarInfo(name=name)
    info.type = tarfile.DIRTYPE
    tar.addfile(info)


def add_symlink(tar, name, target):
    info = tarfile.TarInfo(name=name)
    info.type = tarfile.SYMTYPE
    info.linkname = target
    tar.addfile(info)


def add_hardlink(tar, name, target):
    info = tarfile.TarInfo(name=name)
    info.type = tarfile.LNKTYPE
    info.linkname = target
    tar.addfile(info)


def make_archive(directory, builder):
    path = os.path.join(directory, uuid.uuid4().hex + ".tar.gz")
    with tarfile.open(path, "w:gz") as tar:
        builder(tar)
    return path


def test_adversarial_corpus():
    assert os.path.exists(SCRIPT_PATH), f"Agent script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"Agent script {SCRIPT_PATH} is not a file."

    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"

    assert os.path.isdir(clean_dir), f"Clean corpus directory {clean_dir} missing."
    assert os.path.isdir(evil_dir), f"Evil corpus directory {evil_dir} missing."

    clean_files = [f for f in os.listdir(clean_dir) if f.endswith(".tar.gz")]
    evil_files = [f for f in os.listdir(evil_dir) if f.endswith(".tar.gz")]

    assert len(clean_files) > 0, "No clean files found in corpus."
    assert len(evil_files) > 0, "No evil files found in corpus."

    clean_modified = []
    for f in clean_files:
        archive_path = os.path.join(clean_dir, f)
        if run_filter(archive_path) != 0:
            clean_modified.append(f)

    evil_bypassed = []
    for f in evil_files:
        archive_path = os.path.join(evil_dir, f)
        if run_filter(archive_path) != 1:
            evil_bypassed.append(f)

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified (rejected instead of accepted): {', '.join(clean_modified)}")

    assert not errors, " | ".join(errors)


def test_generated_archives_with_undisclosed_paths():
    assert os.path.exists(SCRIPT_PATH), f"Agent script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"Agent script {SCRIPT_PATH} is not a file."

    directory = tempfile.mkdtemp(prefix=uuid.uuid4().hex + "_")
    token = uuid.uuid4().hex
    cases = []

    cases.append((make_archive(directory, lambda t: add_file(
        t, f"docs/{token}.md", b"Metadata:\nauthor: remote-writer\n\nOrdinary documentation.\n"
    )), 0))

    def nested_clean(t):
        add_dir(t, f"payload_{token}")
        add_dir(t, f"payload_{token}/chapters")
        add_file(t, f"payload_{token}/chapters/intro.md", b"# Introduction\nSafe text.\n")
        add_file(t, f"payload_{token}/asset.bin", os.urandom(64))
    cases.append((make_archive(directory, nested_clean), 0))

    cases.append((make_archive(directory, lambda t: add_file(
        t, f"notes/{token}.txt", b"This non-markdown file mentions " + TRIGGER + b"."
    )), 0))

    def internal_symlink(t):
        add_dir(t, f"manual_{token}")
        add_file(t, f"manual_{token}/guide.md", b"# Safe guide\n")
        add_symlink(t, f"manual_{token}/latest.md", "guide.md")
    cases.append((make_archive(directory, internal_symlink), 0))

    cases.append((make_archive(directory, lambda t: add_file(
        t, f"../{token}.md", b"outside"
    )), 1))

    cases.append((make_archive(directory, lambda t: add_file(
        t, f"folder/{token}/../../../escaped.md", b"outside"
    )), 1))

    cases.append((make_archive(directory, lambda t: add_file(
        t, f"/tmp/{token}.md", b"absolute"
    )), 1))

    cases.append((make_archive(directory, lambda t: add_symlink(
        t, f"links/{token}", "/etc"
    )), 1))

    cases.append((make_archive(directory, lambda t: add_symlink(
        t, f"links/{token}", "../../outside"
    )), 1))

    cases.append((make_archive(directory, lambda t: add_hardlink(
        t, f"links/{token}", "../../../etc/passwd"
    )), 1))

    def backdoor_archive(t):
        add_file(t, f"content/{uuid.uuid4().hex}.md",
                 b"Metadata:\nauthor: x\nflag: " + TRIGGER + b"\n\nBody\n")
        add_file(t, f"content/{uuid.uuid4().hex}.txt", b"otherwise ordinary")
    cases.append((make_archive(directory, backdoor_archive), 1))

    malformed = os.path.join(directory, uuid.uuid4().hex + ".tar.gz")
    with open(malformed, "wb") as f:
        f.write(os.urandom(97))
    cases.append((malformed, 1))

    random.SystemRandom().shuffle(cases)
    failures = []
    for archive_path, expected in cases:
        actual = run_filter(archive_path)
        if actual != expected:
            failures.append(
                f"{os.path.basename(archive_path)}: expected exit {expected}, got {actual}"
            )

    assert not failures, "Generated archive failures: " + " | ".join(failures)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
