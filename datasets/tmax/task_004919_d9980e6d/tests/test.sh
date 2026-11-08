#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import pathlib
import secrets
import subprocess
import tarfile
import tempfile
import time

import pytest

ARCHIVER = "/home/user/archiver"
SOURCE = "/home/user/archiver.c"
HOT = "/home/user/hot_data"
COLD = "/home/user/cold_archive"
LOG = "/home/user/audit.log"


def archive_payload(path, expected_name):
    try:
        with tarfile.open(path, "r:gz") as tar:
            members = [m for m in tar.getmembers() if m.isfile()]
            matching = [m for m in members if m.name.lstrip("./") == expected_name]
            assert matching, f"Archive {path} does not contain regular file {expected_name}."
            assert len(members) == 1, f"Archive {path} contains unexpected regular files."
            extracted = tar.extractfile(matching[0])
            assert extracted is not None
            return extracted.read()
    except (tarfile.TarError, OSError) as exc:
        pytest.fail(f"Archive {path} is not a valid gzip-compressed tar archive: {exc}")


def matching_archiver_pids():
    result = []
    for entry in pathlib.Path("/proc").iterdir():
        if not entry.name.isdigit():
            continue
        try:
            exe = os.path.realpath(entry / "exe")
            raw = (entry / "cmdline").read_bytes()
            argv = [x.decode(errors="replace") for x in raw.split(b"\0") if x]
        except (OSError, PermissionError):
            continue
        if exe == ARCHIVER and len(argv) == 3 and argv[1:] == [HOT, COLD]:
            result.append(int(entry.name))
    return result


def stop_archivers():
    for pid in matching_archiver_pids():
        try:
            os.kill(pid, 15)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while matching_archiver_pids() and time.time() < deadline:
        time.sleep(0.05)
    for pid in matching_archiver_pids():
        try:
            os.kill(pid, 9)
        except ProcessLookupError:
            pass


def wait_for_archiving(proc, original, archive, timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        assert proc.poll() is None, "Archiver exited while waiting for an event."
        if not original.exists() and archive.is_file():
            return
        time.sleep(0.05)
    pytest.fail(f"Archiver did not process {original.name} within {timeout} seconds.")


def exercise(binary):
    token = secrets.token_hex(8)
    with tempfile.TemporaryDirectory(prefix="archiver-watch-") as watch, \
         tempfile.TemporaryDirectory(prefix="archiver-cold-") as cold:
        watch_path = pathlib.Path(watch)
        cold_path = pathlib.Path(cold)
        cases = {
            f"probe_{token}_a.txt": b"generated verifier payload: " + secrets.token_bytes(73),
            f"probe_{token}_b.bin": secrets.token_bytes(1024),
            f"probe_{token}_c.log": b"[DYNAMIC] " + secrets.token_bytes(211),
        }
        log_start = os.path.getsize(LOG)
        proc = subprocess.Popen(
            [binary, watch, cold],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        try:
            time.sleep(0.5)
            assert proc.poll() is None, "Archiver did not remain running after startup."
            for name, payload in cases.items():
                original = watch_path / name
                archive = cold_path / f"{name}.tar.gz"
                with open(original, "wb") as handle:
                    handle.write(payload)
                    handle.flush()
                    os.fsync(handle.fileno())
                wait_for_archiving(proc, original, archive)
                assert archive_payload(archive, name) == payload, \
                    f"Archived contents for {name} differ from the written bytes."
            assert proc.poll() is None, "Archiver did not remain running after multiple events."
            with open(LOG, "rb") as handle:
                handle.seek(log_start)
                added_lines = handle.read().decode(errors="replace").splitlines()
            for name in cases:
                expected = f"ARCHIVED AND VERIFIED: {name}"
                assert expected in added_lines, f"Missing exact dynamic audit entry: {expected}"
        finally:
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait(timeout=2)


def test_complete_workflow():
    # Preserve the original executable and source assertions.
    assert os.path.isfile(ARCHIVER), f"Executable {ARCHIVER} does not exist."
    assert os.access(ARCHIVER, os.X_OK), f"File {ARCHIVER} is not executable."
    with open(ARCHIVER, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", f"{ARCHIVER} is not an ELF executable."

    assert os.path.isfile(SOURCE), f"Source code {SOURCE} does not exist."
    source_text = pathlib.Path(SOURCE).read_text()
    assert "sys/inotify.h" in source_text, f"{SOURCE} does not include sys/inotify.h"
    assert "IN_CLOSE_WRITE" in source_text, f"{SOURCE} does not use IN_CLOSE_WRITE"

    assert os.path.isdir(HOT), f"Directory {HOT} does not exist."
    files = os.listdir(HOT)
    assert len(files) == 0, f"Directory {HOT} is not empty. Contains: {files}"

    assert os.path.isdir(COLD), f"Directory {COLD} does not exist."
    expected_payloads = {
        "report.csv": b"id,value\n1,100",
        "system.log": b"[WARN] Disk space running low",
    }
    for filename in ["report.csv", "image.bin", "system.log"]:
        archive = os.path.join(COLD, filename + ".tar.gz")
        assert os.path.isfile(archive), f"Archive {archive} does not exist."
        payload = archive_payload(archive, filename)
        if filename == "image.bin":
            assert len(payload) == 1024, "Archived image.bin is not exactly 1024 bytes."
        else:
            assert payload == expected_payloads[filename], \
                f"Archived contents for {filename} do not match the required text."

    assert os.path.isfile(LOG), f"Log file {LOG} does not exist."
    log_text = pathlib.Path(LOG).read_text()
    for filename in ["report.csv", "image.bin", "system.log"]:
        line = f"ARCHIVED AND VERIFIED: {filename}"
        assert line in log_text, f"Audit log does not contain expected line: '{line}'"

    # The requested background daemon must actually still be alive with the right arguments.
    assert matching_archiver_pids(), \
        "No running /home/user/archiver process is watching the required directories."
    stop_archivers()

    # The source must compile, independently of the submitted executable.
    rebuilt = "/tmp/archiver_rebuilt"
    compiled = subprocess.run(
        ["gcc", SOURCE, "-o", rebuilt],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert compiled.returncode == 0, f"archiver.c does not compile:\n{compiled.stderr}"

    # Exactly two user arguments are required.
    for bad_args in ([], [HOT, COLD, "extra"]):
        try:
            result = subprocess.run(
                [ARCHIVER] + bad_args,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=2,
            )
        except subprocess.TimeoutExpired:
            pytest.fail(f"Archiver accepted invalid argument list: {bad_args}")
        assert result.returncode != 0, f"Archiver accepted invalid argument list: {bad_args}"

    # Exercise both the delivered executable and a fresh build of the delivered C source
    # with unpredictable filenames and bytes.
    exercise(ARCHIVER)
    exercise(rebuilt)

    # Leave the required daemon running after verification as instructed.
    final_proc = subprocess.Popen(
        [ARCHIVER, HOT, COLD],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    time.sleep(0.5)
    assert final_proc.poll() is None, "Archiver would not remain running for final state."
    assert matching_archiver_pids(), "Final archiver process has incorrect executable or arguments."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
