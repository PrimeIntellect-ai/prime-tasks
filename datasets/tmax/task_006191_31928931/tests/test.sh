#!/bin/bash
set -e
mkdir -p /logs/verifier
export RUSTUP_HOME=/opt/rust
export CARGO_HOME=/opt/cargo
export PATH=/opt/cargo/bin:$PATH

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import hashlib
import io
import json
import os
import select
import shutil
import struct
import subprocess
import tarfile
import tempfile
import time

import pytest

DEST_DIR = "/home/user/archive_dest"
INPUT_ARCHIVE = "/home/user/incoming/nested_logs.tar.gz"
CONSOLIDATED_TAR = os.path.join(DEST_DIR, "consolidated.tar.gz")
MANIFEST_JSON = os.path.join(DEST_DIR, "manifest.json")

EXPECTED_HASHES = {
    "app_2020.log": "c830ddad592f6cefe387e3ffb78bf0198cded24128f73117565b9ceee313c048",
    "auth_2021.log": "81bbfe2b2f676239162dbdb7579bd66c429007f50244431e649089f5c4041b31",
}


def test_consolidated_tar_exists():
    assert os.path.isfile(CONSOLIDATED_TAR), f"File {CONSOLIDATED_TAR} does not exist."


def test_manifest_exists():
    assert os.path.isfile(MANIFEST_JSON), f"File {MANIFEST_JSON} does not exist."


def test_no_tmp_files():
    for name in os.listdir(DEST_DIR):
        assert not name.endswith(".tmp"), f"Found temporary file {name} in {DEST_DIR}, atomicity requirement likely violated."


def test_manifest_content():
    with open(MANIFEST_JSON, "r") as f:
        try:
            manifest = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("manifest.json is not valid JSON.")
    assert manifest == EXPECTED_HASHES, f"Manifest contents do not match expected hashes. Got: {manifest}"


def validate_archive(path, expected):
    with tempfile.TemporaryDirectory() as tmpdir:
        try:
            with tarfile.open(path, "r:gz") as tar:
                members = tar.getmembers()
                assert all(m.isfile() for m in members), "Archive contains a non-regular-file entry."
                assert all("/" not in m.name and m.name not in (".", "..") for m in members), "Archive is not flat."
                assert {m.name for m in members} == set(expected), "Archive members do not match expected flat files."
                tar.extractall(path=tmpdir)
        except tarfile.TarError:
            pytest.fail("consolidated.tar.gz is not a valid gzipped tar archive.")

        extracted_files = os.listdir(tmpdir)
        assert set(extracted_files) == set(expected), f"Extracted files {extracted_files} do not match expected flat files."
        for filename, expected_hash in expected.items():
            filepath = os.path.join(tmpdir, filename)
            assert os.path.isfile(filepath), f"File {filename} not found at the root of the archive."
            with open(filepath, "rb") as f:
                file_hash = hashlib.sha256(f.read()).hexdigest()
            assert file_hash == expected_hash, f"Hash for {filename} in archive does not match expected hash."


def test_consolidated_tar_contents():
    validate_archive(CONSOLIDATED_TAR, EXPECTED_HASHES)


def find_and_build_rust_program():
    manifests = []
    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if d not in {"target", ".cargo", ".rustup"}]
        if "Cargo.toml" in files:
            manifests.append(os.path.join(root, "Cargo.toml"))

    manifests.sort(key=lambda p: (p != "/home/user/consolidator/Cargo.toml", p))
    build_errors = []
    for manifest in manifests:
        cmd = ["/opt/cargo/bin/cargo", "build", "--offline", "--bins", "--message-format=json", "--manifest-path", manifest]
        result = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=180)
        if result.returncode != 0:
            build_errors.append(f"{manifest}: {result.stderr[-1000:]}")
            continue

        executables = []
        for line in result.stdout.splitlines():
            try:
                message = json.loads(line)
            except json.JSONDecodeError:
                continue
            if message.get("reason") == "compiler-artifact" and "bin" in message.get("target", {}).get("kind", []):
                executable = message.get("executable")
                if executable:
                    executables.append((message["target"].get("name", ""), executable))

        preferred = [p for name, p in executables if name == "consolidator"]
        if len(preferred) == 1:
            return preferred[0], os.path.dirname(manifest)
        if len(executables) == 1:
            return executables[0][1], os.path.dirname(manifest)
        if executables:
            build_errors.append(f"{manifest}: multiple binaries and none is named consolidator")

    detail = "\n".join(build_errors)
    pytest.fail("No buildable Rust Cargo binary was found under /home/user. " + detail)


def add_bytes(tar, name, data):
    info = tarfile.TarInfo(name)
    info.size = len(data)
    info.mode = 0o644
    tar.addfile(info, io.BytesIO(data))


def make_inner(entries):
    output = io.BytesIO()
    with tarfile.open(fileobj=output, mode="w:gz") as tar:
        for name, data in entries.items():
            add_bytes(tar, name, data)
    return output.getvalue()


def write_dynamic_nested_archive(path):
    token = os.urandom(24).hex().encode("ascii")
    files = {
        "dynamic_alpha.log": b"alpha generated by verifier: " + token + b"\n",
        "dynamic_beta.log": b"beta generated by verifier: " + token[::-1] + b"\n",
        "dynamic_gamma.log": os.urandom(79),
    }
    first = make_inner({"old/tree/dynamic_alpha.log": files["dynamic_alpha.log"], "ignore.txt": b"not a log"})
    second = make_inner({"elsewhere/dynamic_beta.log": files["dynamic_beta.log"], "dynamic_gamma.log": files["dynamic_gamma.log"]})
    with tarfile.open(path, "w:gz") as outer:
        add_bytes(outer, "nested/first.tar.gz", first)
        add_bytes(outer, "second.tar.gz", second)
    return {name: hashlib.sha256(data).hexdigest() for name, data in files.items()}


IN_MODIFY = 0x00000002
IN_CLOSE_WRITE = 0x00000008
IN_MOVED_FROM = 0x00000040
IN_MOVED_TO = 0x00000080
IN_CREATE = 0x00000100
EVENT_STRUCT = struct.Struct("iIII")


def run_with_atomicity_monitor(executable, cwd):
    libc = ctypes.CDLL(None, use_errno=True)
    fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
    assert fd >= 0, f"inotify_init1 failed: errno {ctypes.get_errno()}"
    mask = IN_CREATE | IN_MODIFY | IN_CLOSE_WRITE | IN_MOVED_FROM | IN_MOVED_TO
    wd = libc.inotify_add_watch(fd, DEST_DIR.encode(), mask)
    assert wd >= 0, f"inotify_add_watch failed: errno {ctypes.get_errno()}"

    events = []
    output = tempfile.TemporaryFile()
    try:
        proc = subprocess.Popen([executable], cwd=cwd, stdout=output, stderr=subprocess.STDOUT)
        deadline = time.monotonic() + 60
        while proc.poll() is None:
            if time.monotonic() > deadline:
                proc.kill()
                proc.wait()
                pytest.fail("Rust program timed out during behavioral verification.")
            ready, _, _ = select.select([fd], [], [], 0.1)
            if ready:
                events.extend(read_inotify_events(fd))
        time.sleep(0.05)
        events.extend(read_inotify_events(fd))
        output.seek(0)
        program_output = output.read().decode(errors="replace")
        assert proc.returncode == 0, f"Rust program exited with {proc.returncode}: {program_output[-2000:]}"
    finally:
        output.close()
        os.close(fd)

    for final_name in ("consolidated.tar.gz", "manifest.json"):
        moved_to = [(cookie, name) for mask_value, cookie, name in events if mask_value & IN_MOVED_TO and name == final_name]
        assert moved_to, f"{final_name} was not atomically renamed into place."
        valid = False
        for cookie, _ in moved_to:
            sources = [name for mask_value, source_cookie, name in events if mask_value & IN_MOVED_FROM and source_cookie == cookie]
            for source in sources:
                if source and source != final_name:
                    created = any((mask_value & IN_CREATE) and name == source for mask_value, _, name in events)
                    written = any((mask_value & (IN_MODIFY | IN_CLOSE_WRITE)) and name == source for mask_value, _, name in events)
                    if created and written:
                        valid = True
        assert valid, f"{final_name} was not written to a destination-directory temporary file before atomic rename."


def read_inotify_events(fd):
    result = []
    while True:
        try:
            data = os.read(fd, 65536)
        except BlockingIOError:
            break
        if not data:
            break
        offset = 0
        while offset + EVENT_STRUCT.size <= len(data):
            wd, mask, cookie, name_len = EVENT_STRUCT.unpack_from(data, offset)
            offset += EVENT_STRUCT.size
            raw_name = data[offset:offset + name_len]
            offset += name_len
            name = raw_name.split(b"\0", 1)[0].decode(errors="surrogateescape")
            result.append((mask, cookie, name))
    return result


def test_rust_program_executes_and_uses_atomic_writes():
    executable, cwd = find_and_build_rust_program()
    assert os.path.isfile(executable) and os.access(executable, os.X_OK), "Compiled Rust binary is not executable."

    with tempfile.TemporaryDirectory() as backup_dir:
        input_backup = os.path.join(backup_dir, "nested_logs.tar.gz")
        tar_backup = os.path.join(backup_dir, "consolidated.tar.gz")
        manifest_backup = os.path.join(backup_dir, "manifest.json")
        shutil.copy2(INPUT_ARCHIVE, input_backup)
        shutil.copy2(CONSOLIDATED_TAR, tar_backup)
        shutil.copy2(MANIFEST_JSON, manifest_backup)
        try:
            expected = write_dynamic_nested_archive(INPUT_ARCHIVE)
            for name in os.listdir(DEST_DIR):
                path = os.path.join(DEST_DIR, name)
                if os.path.isdir(path) and not os.path.islink(path):
                    shutil.rmtree(path)
                else:
                    os.unlink(path)

            run_with_atomicity_monitor(executable, cwd)

            assert os.path.isfile(CONSOLIDATED_TAR), "Rust program did not recreate consolidated.tar.gz."
            assert os.path.isfile(MANIFEST_JSON), "Rust program did not recreate manifest.json."
            with open(MANIFEST_JSON, "r") as f:
                manifest = json.load(f)
            assert manifest == expected, f"Rust program failed verifier-generated input. Got: {manifest}"
            validate_archive(CONSOLIDATED_TAR, expected)
            test_no_tmp_files()
        finally:
            shutil.copy2(input_backup, INPUT_ARCHIVE)
            shutil.copy2(tar_backup, CONSOLIDATED_TAR)
            shutil.copy2(manifest_backup, MANIFEST_JSON)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
