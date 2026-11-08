#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import pwd
import shutil
import subprocess
import tarfile
import tempfile

import pytest

LOGS_DIR = "/home/user/data/logs"
ARCHIVE_DIR = "/home/user/data/archive"
PLACEHOLDER = "/home/user/data/offline_placeholder.txt"
SCRIPT = "/home/user/archive_logs.py"
EXPECTED_LOGS = ["app_alpha.log", "app_beta.log", "app_gamma.log"]
CHUNK_SIZE = 1048576


def chunk_files():
    return sorted(
        f for f in os.listdir(ARCHIVE_DIR)
        if f.startswith("chunk_") and f.endswith(".dat")
    )


def reconstruct(path):
    with open(path, "wb") as output:
        for name in chunk_files():
            with open(os.path.join(ARCHIVE_DIR, name), "rb") as chunk:
                shutil.copyfileobj(chunk, output)


def assert_symlinks():
    for log_name in EXPECTED_LOGS:
        log_path = os.path.join(LOGS_DIR, log_name)
        assert os.path.islink(log_path), f"Log file {log_path} is not a symlink."
        target = os.readlink(log_path)
        assert target == PLACEHOLDER, (
            f"Symlink {log_path} points to {target}, expected {PLACEHOLDER}."
        )


def assert_chunks_sized_correctly():
    chunks = chunk_files()
    assert len(chunks) > 0, "No chunk files found in the archive directory."

    for i, name in enumerate(chunks):
        expected_name = f"chunk_{i:03d}.dat"
        assert name == expected_name, f"Expected chunk name {expected_name}, found {name}."

    for name in chunks[:-1]:
        size = os.path.getsize(os.path.join(ARCHIVE_DIR, name))
        assert size == CHUNK_SIZE, f"Chunk {name} has size {size}, expected {CHUNK_SIZE}."

    last_size = os.path.getsize(os.path.join(ARCHIVE_DIR, chunks[-1]))
    assert 0 < last_size <= CHUNK_SIZE, (
        f"Last chunk {chunks[-1]} has invalid size {last_size}."
    )


def test_script_exists():
    assert os.path.isfile(SCRIPT), f"Required Python script {SCRIPT} does not exist."


def test_logs_are_symlinks():
    assert_symlinks()


def test_archive_chunks_exist_and_sized_correctly():
    assert_chunks_sized_correctly()


def test_reconstruct_and_verify_tarball():
    chunks = chunk_files()
    assert len(chunks) > 0, "No chunk files found to reconstruct."

    with tempfile.NamedTemporaryFile(delete=False, suffix=".tar.gz") as temp_tar:
        temp_tar_path = temp_tar.name
    try:
        reconstruct(temp_tar_path)
        assert tarfile.is_tarfile(temp_tar_path), "Reconstructed file is not a valid tar archive."
        with tarfile.open(temp_tar_path, "r:gz") as tar:
            members = tar.getnames()
            member_basenames = [os.path.basename(m) for m in members]
            for log in EXPECTED_LOGS:
                assert log in member_basenames, (
                    f"Expected log file {log} not found in reconstructed tarball."
                )
    finally:
        if os.path.exists(temp_tar_path):
            os.remove(temp_tar_path)


def test_script_on_fresh_random_logs_with_atomic_writes():
    # Exercise the submitted artifact on verifier-generated data, whose contents
    # were unavailable when the submission was created.
    for directory in (LOGS_DIR, ARCHIVE_DIR):
        for name in os.listdir(directory):
            path = os.path.join(directory, name)
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.unlink(path)

    user = pwd.getpwnam("user")
    expected = {}
    for i, name in enumerate(EXPECTED_LOGS):
        data = os.urandom(700000 + i * 137)
        expected[name] = data
        path = os.path.join(LOGS_DIR, name)
        with open(path, "wb") as f:
            f.write(data)
        os.chown(path, user.pw_uid, user.pw_gid)

    audit_dir = tempfile.mkdtemp(prefix="archive_atomic_audit_", dir="/tmp")
    os.chmod(audit_dir, 0o777)
    trace_path = os.path.join(audit_dir, "trace.jsonl")
    sitecustomize = r'''
import hashlib
import json
import os
import sys

_trace = os.environ.get("ARCHIVE_AUDIT_TRACE")
_fd = os.open(_trace, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o666)
_busy = False

def _resolve(path, dirfd=-1):
    if not isinstance(path, (str, bytes, os.PathLike)):
        return None
    path = os.fsdecode(path)
    if os.path.isabs(path):
        return os.path.normpath(path)
    if isinstance(dirfd, int) and dirfd >= 0:
        try:
            base = os.readlink(f"/proc/self/fd/{dirfd}")
        except OSError:
            base = os.getcwd()
    else:
        base = os.getcwd()
    return os.path.normpath(os.path.join(base, path))

def _emit(record):
    global _busy
    if _busy:
        return
    _busy = True
    try:
        os.write(_fd, (json.dumps(record, sort_keys=True) + "\n").encode())
    finally:
        _busy = False

def _hook(event, args):
    global _busy
    if _busy:
        return
    if event == "open":
        path, mode, flags = args
        resolved = _resolve(path)
        access = flags & os.O_ACCMODE
        writing = access != os.O_RDONLY or bool(
            flags & (os.O_CREAT | os.O_TRUNC | os.O_APPEND)
        )
        if resolved and writing:
            _emit({"event": "write_open", "path": resolved})
    elif event == "os.rename":
        src, dst, srcfd, dstfd = args
        source = _resolve(src, srcfd)
        destination = _resolve(dst, dstfd)
        record = {"event": "rename", "src": source, "dst": destination}
        if source:
            try:
                h = hashlib.sha256()
                with open(source, "rb") as f:
                    while True:
                        block = f.read(1024 * 1024)
                        if not block:
                            break
                        h.update(block)
                record["size_at_rename"] = os.path.getsize(source)
                record["sha256_at_rename"] = h.hexdigest()
            except OSError as exc:
                record["snapshot_error"] = repr(exc)
        _emit(record)

sys.addaudithook(_hook)
'''
    with open(os.path.join(audit_dir, "sitecustomize.py"), "w") as f:
        f.write(sitecustomize)
    os.chmod(os.path.join(audit_dir, "sitecustomize.py"), 0o644)

    env = os.environ.copy()
    env["PYTHONPATH"] = audit_dir
    env["ARCHIVE_AUDIT_TRACE"] = trace_path

    def become_user():
        os.setgid(user.pw_gid)
        os.setuid(user.pw_uid)

    result = subprocess.run(
        ["python3", SCRIPT],
        cwd="/home/user",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
        preexec_fn=become_user,
    )
    assert result.returncode == 0, (
        f"archive_logs.py failed on fresh logs (exit {result.returncode}).\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    assert_symlinks()
    assert_chunks_sized_correctly()
    assert len(chunk_files()) >= 2, "Fresh test data should produce multiple chunks."

    rebuilt = os.path.join(audit_dir, "rebuilt.tar.gz")
    reconstruct(rebuilt)
    assert tarfile.is_tarfile(rebuilt), "Freshly reconstructed chunks are not a tar archive."

    with tarfile.open(rebuilt, "r:gz") as tar:
        for name, original_data in expected.items():
            matches = [m for m in tar.getmembers() if os.path.basename(m.name) == name]
            assert len(matches) == 1, f"Expected exactly one archived member named {name}."
            member = matches[0]
            assert member.isfile(), f"Archived member {name} is not a regular file."
            extracted = tar.extractfile(member)
            assert extracted is not None
            archived_data = extracted.read()
            assert archived_data == original_data, (
                f"Archived contents for {name} do not match the original random log data."
            )

    assert os.path.exists(trace_path), "No filesystem-operation audit trace was produced."
    with open(trace_path) as f:
        records = [json.loads(line) for line in f if line.strip()]

    direct_writes = {
        r.get("path") for r in records
        if r.get("event") == "write_open"
        and r.get("path", "").startswith(ARCHIVE_DIR + os.sep)
        and r.get("path", "").endswith(".dat")
    }
    assert not direct_writes, (
        "Final .dat chunk paths were opened for writing instead of being published only by rename: "
        + ", ".join(sorted(direct_writes))
    )

    for name in chunk_files():
        final_path = os.path.join(ARCHIVE_DIR, name)
        renames = [
            r for r in records
            if r.get("event") == "rename" and r.get("dst") == final_path
        ]
        assert renames, f"Chunk {name} was not atomically renamed into its final path."
        rename = renames[-1]
        source = rename.get("src")
        assert source and os.path.dirname(source) == ARCHIVE_DIR, (
            f"Chunk {name} was not renamed from a temporary file in the archive directory."
        )
        assert source != final_path and not source.endswith(".dat"), (
            f"Chunk {name} was not published from a distinct temporary filename."
        )
        with open(final_path, "rb") as f:
            final_data = f.read()
        assert rename.get("size_at_rename") == len(final_data), (
            f"Temporary file for {name} was not complete at rename time."
        )
        assert rename.get("sha256_at_rename") == hashlib.sha256(final_data).hexdigest(), (
            f"Contents of {name} changed after it was renamed into place."
        )


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
