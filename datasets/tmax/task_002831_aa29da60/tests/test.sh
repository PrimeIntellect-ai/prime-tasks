#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import io
import os
import re
import shutil
import signal
import subprocess
import tarfile
import tempfile
import time
import uuid

import pytest

EVIL_DIR = "/app/corpora/evil"
CLEAN_DIR = "/app/corpora/clean"
MINITAR_BIN = "/app/minitar-0.1/minitar"
WATCH_SCRIPT = "/app/watch_and_extract.sh"
INCOMING_DIR = "/app/incoming"
MANIFEST = "/app/extraction_manifest.txt"
ERROR_LOG = "/app/extraction_errors.log"


def run_minitar(archive, cwd):
    return subprocess.run(
        [MINITAR_BIN, "-x", "-f", archive],
        cwd=cwd,
        capture_output=True,
        text=True,
        timeout=10,
    )


def regular_members(archive):
    with tarfile.open(archive, "r") as tf:
        return {
            member.name: tf.extractfile(member).read()
            for member in tf.getmembers()
            if member.isfile()
        }


def make_tar(path, entries):
    with tarfile.open(path, "w") as tf:
        for name, data in entries:
            info = tarfile.TarInfo(name=name)
            info.size = len(data)
            info.mode = 0o644
            tf.addfile(info, io.BytesIO(data))


def wait_for(predicate, timeout=12):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if predicate():
            return True
        time.sleep(0.1)
    return False


def read_text(path):
    try:
        with open(path, "r", errors="replace") as f:
            return f.read()
    except FileNotFoundError:
        return ""


def find_named(name):
    matches = []
    for root in ("/app", "/tmp", "/home", "/root"):
        if not os.path.exists(root):
            continue
        for current, dirs, files in os.walk(root):
            if name in files or name in dirs:
                matches.append(os.path.join(current, name))
    return matches


def publish_complete_tar(staging, destination):
    # CREATE watchers see a complete linked file, while CLOSE_WRITE watchers are
    # triggered by the subsequent open/close.
    os.link(staging, destination)
    with open(destination, "ab"):
        pass


def test_minitar_binary_exists():
    assert os.path.isfile(MINITAR_BIN), f"Expected binary {MINITAR_BIN} is missing. Did you compile it?"
    assert os.access(MINITAR_BIN, os.X_OK), f"Expected {MINITAR_BIN} to be executable."
    with open(MINITAR_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "minitar must be the compiled native binary requested by the task."


def test_adversarial_corpus():
    assert os.path.isdir(EVIL_DIR), f"Evil corpus directory {EVIL_DIR} missing."
    assert os.path.isdir(CLEAN_DIR), f"Clean corpus directory {CLEAN_DIR} missing."

    evil_files = sorted(f for f in os.listdir(EVIL_DIR) if f.endswith(".tar"))
    clean_files = sorted(f for f in os.listdir(CLEAN_DIR) if f.endswith(".tar"))
    assert evil_files, "No evil tar files found."
    assert clean_files, "No clean tar files found."

    evil_bypassed = []
    clean_modified = []

    for filename in evil_files:
        archive = os.path.join(EVIL_DIR, filename)
        with tempfile.TemporaryDirectory() as cwd:
            result = run_minitar(archive, cwd)
            if result.returncode != 1 or result.stdout != f"REJECT: {archive}\n" or os.listdir(cwd):
                evil_bypassed.append(filename)

    for filename in clean_files:
        archive = os.path.join(CLEAN_DIR, filename)
        expected = regular_members(archive)
        with tempfile.TemporaryDirectory() as cwd:
            result = run_minitar(archive, cwd)
            actual = {}
            for current, _, files in os.walk(cwd):
                for name in files:
                    path = os.path.join(current, name)
                    rel = os.path.relpath(path, cwd)
                    with open(path, "rb") as f:
                        actual[rel] = f.read()
            if result.returncode != 0 or result.stdout != f"ACCEPT: {archive}\n" or actual != expected:
                clean_modified.append(filename)

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")
    if errors:
        pytest.fail("; ".join(errors))


def test_generated_archives_are_parsed_and_extracted_atomically():
    token = uuid.uuid4().hex
    with tempfile.TemporaryDirectory() as archive_dir:
        clean_archive = os.path.join(archive_dir, f"evil-looking-{token}.tar")
        clean_entries = [
            (f"alpha_{token}.txt", os.urandom(37)),
            (f"report..{token}.bin", os.urandom(913)),
        ]
        make_tar(clean_archive, clean_entries)
        with tempfile.TemporaryDirectory() as cwd:
            result = run_minitar(clean_archive, cwd)
            assert result.returncode == 0
            assert result.stdout == f"ACCEPT: {clean_archive}\n"
            for name, data in clean_entries:
                with open(os.path.join(cwd, name), "rb") as f:
                    assert f.read() == data
            assert sorted(os.listdir(cwd)) == sorted(name for name, _ in clean_entries)

        cases = [
            [(f"../escape_{token}", b"escape")],
            [(f"sub/../../escape2_{token}", b"escape")],
            [(f"/tmp/absolute_escape_{token}", b"escape")],
            [(f"would_extract_{token}.txt", b"must not appear"), (f"../late_escape_{token}", b"escape")],
        ]
        for index, entries in enumerate(cases):
            archive = os.path.join(archive_dir, f"innocent-{token}-{index}.tar")
            make_tar(archive, entries)
            with tempfile.TemporaryDirectory() as cwd:
                result = run_minitar(archive, cwd)
                assert result.returncode == 1
                assert result.stdout == f"REJECT: {archive}\n"
                assert os.listdir(cwd) == [], "A rejected archive extracted an entry before rejection."

        assert not os.path.exists(f"/tmp/absolute_escape_{token}")


def test_watch_script_exists():
    assert os.path.isfile(WATCH_SCRIPT), f"Expected script {WATCH_SCRIPT} is missing."
    assert os.path.getsize(WATCH_SCRIPT) > 10, f"{WATCH_SCRIPT} is empty or too short."


def test_watcher_end_to_end():
    token = uuid.uuid4().hex
    marker = f"VERIFIER_STDERR_{token}"
    real_binary = f"{MINITAR_BIN}.verifier-real-{token}"
    proc = None
    staging_paths = []

    os.makedirs(INCOMING_DIR, exist_ok=True)
    for name in os.listdir(INCOMING_DIR):
        path = os.path.join(INCOMING_DIR, name)
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)
    for path in (MANIFEST, ERROR_LOG):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    os.rename(MINITAR_BIN, real_binary)
    try:
        with open(MINITAR_BIN, "w") as f:
            f.write("#!/bin/sh\n")
            f.write(f"printf '%s %s\\n' '{marker}' \"$*\" >&2\n")
            f.write(f"exec '{real_binary}' \"$@\"\n")
        os.chmod(MINITAR_BIN, 0o755)

        proc = subprocess.Popen(
            ["/bin/bash", WATCH_SCRIPT],
            cwd="/app/minitar-0.1",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            start_new_session=True,
        )
        time.sleep(1)
        assert proc.poll() is None, "watch_and_extract.sh terminated instead of monitoring continuously."

        clean_names = [f"watched_a_{token}.txt", f"watched_b_{token}.bin"]
        clean_data = [os.urandom(71), os.urandom(1041)]
        clean_archive = os.path.join(INCOMING_DIR, f"upload_{token}.tar")
        clean_stage = f"/app/.watch-stage-clean-{token}"
        staging_paths.append(clean_stage)
        make_tar(clean_stage, list(zip(clean_names, clean_data)))
        publish_complete_tar(clean_stage, clean_archive)

        def clean_processed():
            errors = read_text(ERROR_LOG)
            return (
                marker in errors
                and os.path.basename(clean_archive) in errors
                and all(find_named(name) for name in clean_names)
                and all(name in read_text(MANIFEST) for name in clean_names)
            )

        assert wait_for(clean_processed), "Watcher did not invoke minitar, extract the clean upload, log stderr, and update the manifest."

        manifest = read_text(MANIFEST)
        for name, data in zip(clean_names, clean_data):
            paths = find_named(name)
            assert paths, f"Watcher did not extract {name}."
            assert any(open(path, "rb").read() == data for path in paths)
            digest = hashlib.sha256(data).hexdigest()
            assert any(re.match(rf"^{digest}  .*{re.escape(name)}$", line) for line in manifest.splitlines()), \
                f"Manifest lacks the required SHA-256 entry for {name}."

        blocked_name = f"blocked_before_reject_{token}.txt"
        escaped_name = f"watch_escape_{token}.txt"
        evil_archive = os.path.join(INCOMING_DIR, f"upload_mixed_{token}.tar")
        evil_stage = f"/app/.watch-stage-evil-{token}"
        staging_paths.append(evil_stage)
        make_tar(evil_stage, [(blocked_name, b"no extraction"), (f"../{escaped_name}", b"escape")])
        publish_complete_tar(evil_stage, evil_archive)

        assert wait_for(lambda: marker in read_text(ERROR_LOG) and os.path.basename(evil_archive) in read_text(ERROR_LOG)), \
            "Watcher did not pass the rejected upload to minitar with stderr redirected to the error log."
        time.sleep(1)
        assert not find_named(blocked_name), "Watcher allowed a rejected archive to extract a safe entry."
        assert not find_named(escaped_name), "Watcher allowed a rejected archive to escape its extraction directory."
        assert blocked_name not in read_text(MANIFEST)
        assert escaped_name not in read_text(MANIFEST)
        assert proc.poll() is None, "Watcher stopped running after processing uploads."
    finally:
        if proc is not None and proc.poll() is None:
            try:
                os.killpg(proc.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                proc.wait(timeout=3)
        try:
            os.unlink(MINITAR_BIN)
        except FileNotFoundError:
            pass
        if os.path.exists(real_binary):
            os.rename(real_binary, MINITAR_BIN)
        for path in staging_paths:
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass


TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
