#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import io
import os
import secrets
import struct
import subprocess
import tarfile
import time
import zipfile


def test_curator_script_exists_and_executable():
    curator_path = "/home/user/curator"
    assert os.path.isfile(curator_path), f"The script {curator_path} does not exist."
    assert os.access(curator_path, os.X_OK), f"The script {curator_path} is not executable."


def test_curated_directory_contents():
    curated_dir = "/home/user/curated"
    assert os.path.isdir(curated_dir), f"Directory {curated_dir} does not exist."

    expected_files = {
        "verified_initial_valid.zip",
        "verified_system_backup_1.tar.gz",
        "verified_data_package.zip"
    }

    actual_files = set(os.listdir(curated_dir))

    missing = expected_files - actual_files
    assert not missing, f"Missing files in curated directory: {missing}"

    unexpected = actual_files - expected_files
    assert not unexpected, f"Unexpected files in curated directory: {unexpected}"


def test_quarantine_directory_contents():
    quarantine_dir = "/home/user/quarantine"
    assert os.path.isdir(quarantine_dir), f"Directory {quarantine_dir} does not exist."

    expected_files = {
        "Bad Start.zip",
        "Broken Archive.tar.gz"
    }

    actual_files = set(os.listdir(quarantine_dir))

    missing = expected_files - actual_files
    assert not missing, f"Missing files in quarantine directory: {missing}"

    unexpected = actual_files - expected_files
    assert not unexpected, f"Unexpected files in quarantine directory: {unexpected}"


def test_dropzone_is_empty_of_target_files():
    dropzone_dir = "/home/user/dropzone"
    assert os.path.isdir(dropzone_dir), f"Directory {dropzone_dir} does not exist."

    files_in_dropzone = os.listdir(dropzone_dir)

    assert "SHUTDOWN" not in files_in_dropzone, "SHUTDOWN file was not deleted from dropzone."

    original_files = {
        "Initial Valid.zip",
        "Bad Start.zip",
        "System Backup 1.tar.gz",
        "Broken Archive.tar.gz",
        "Data package.zip"
    }

    remaining = original_files.intersection(files_in_dropzone)
    assert not remaining, f"Files were left in the dropzone: {remaining}"


def test_no_tmp_files_in_curated():
    curated_dir = "/home/user/curated"
    if os.path.isdir(curated_dir):
        tmp_files = [f for f in os.listdir(curated_dir) if f.endswith(".tmp")]
        assert not tmp_files, f"Found unexpected .tmp files in curated directory: {tmp_files}"


def test_zz_curator_behavior_integrity_watching_shutdown_and_atomic_placement():
    dropzone = "/home/user/dropzone"
    curated = "/home/user/curated"
    quarantine = "/home/user/quarantine"

    for directory in (dropzone, curated, quarantine):
        os.makedirs(directory, exist_ok=True)
        for name in os.listdir(directory):
            path = os.path.join(directory, name)
            if os.path.isdir(path) and not os.path.islink(path):
                import shutil
                shutil.rmtree(path)
            else:
                os.unlink(path)

    token = secrets.token_hex(5)
    startup_zip = f"Startup {token} ZIP Case.zip"
    startup_bad = f"Startup {token} Broken.tar.gz"
    live_tar = f"Live {token} TAR Sample.tar.gz"
    live_bad = f"Live {token} Broken.zip"
    last_zip = f"Last {token} Item.zip"

    def normalized(name):
        return "verified_" + name.lower().replace(" ", "_")

    valid_payloads = {
        startup_zip: ("startup/content.bin", os.urandom(193)),
        live_tar: ("nested/live.txt", os.urandom(257)),
        last_zip: ("last/file.dat", os.urandom(149)),
    }
    corrupt_payloads = {
        startup_bad: b"not a gzip tarball\x00" + os.urandom(41),
        live_bad: b"not a zip archive\x00" + os.urandom(37),
    }
    original_bytes = {}

    def make_zip(path, member, payload):
        with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
            zf.writestr(member, payload)

    def make_tar(path, member, payload):
        with tarfile.open(path, "w:gz") as tf:
            info = tarfile.TarInfo(member)
            info.size = len(payload)
            info.mtime = 1
            tf.addfile(info, io.BytesIO(payload))

    make_zip(os.path.join(dropzone, startup_zip), *valid_payloads[startup_zip])
    with open(os.path.join(dropzone, startup_bad), "wb") as f:
        f.write(corrupt_payloads[startup_bad])
    for name in (startup_zip, startup_bad):
        with open(os.path.join(dropzone, name), "rb") as f:
            original_bytes[name] = f.read()

    libc = ctypes.CDLL(None, use_errno=True)
    libc.inotify_init1.argtypes = [ctypes.c_int]
    libc.inotify_init1.restype = ctypes.c_int
    libc.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
    libc.inotify_add_watch.restype = ctypes.c_int
    IN_CLOSE_WRITE = 0x00000008
    IN_MOVED_FROM = 0x00000040
    IN_MOVED_TO = 0x00000080
    IN_CREATE = 0x00000100
    fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
    assert fd >= 0, "Could not initialize inotify for atomic-placement observation"
    wd = libc.inotify_add_watch(fd, curated.encode(), IN_CLOSE_WRITE | IN_MOVED_FROM | IN_MOVED_TO | IN_CREATE)
    assert wd >= 0, "Could not watch curated directory"
    events = []

    def drain_events():
        while True:
            try:
                data = os.read(fd, 65536)
            except BlockingIOError:
                return
            if not data:
                return
            offset = 0
            while offset + 16 <= len(data):
                event_wd, mask, cookie, length = struct.unpack_from("iIII", data, offset)
                raw_name = data[offset + 16:offset + 16 + length]
                name = raw_name.split(b"\0", 1)[0].decode(errors="replace")
                events.append((mask, cookie, name))
                offset += 16 + length

    def wait_until(predicate, timeout=15, message="condition was not met"):
        deadline = time.time() + timeout
        while time.time() < deadline:
            drain_events()
            if predicate():
                return
            time.sleep(0.05)
        drain_events()
        assert predicate(), message

    proc = None
    stage_dir = f"/tmp/curator-test-{token}"
    os.makedirs(stage_dir, exist_ok=True)
    try:
        proc = subprocess.Popen(
            ["/home/user/curator"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

        time.sleep(0.35)
        assert proc.poll() is None, "Curator did not remain running while waiting for new files"

        startup_final = normalized(startup_zip)
        wait_until(
            lambda: os.path.isfile(os.path.join(curated, startup_final))
                    and os.path.isfile(os.path.join(quarantine, startup_bad)),
            message="Curator did not process archives already present at startup",
        )
        assert proc.poll() is None, "Curator exited before SHUTDOWN appeared"

        staged_tar = os.path.join(stage_dir, live_tar)
        make_tar(staged_tar, *valid_payloads[live_tar])
        with open(staged_tar, "rb") as f:
            original_bytes[live_tar] = f.read()
        os.replace(staged_tar, os.path.join(dropzone, live_tar))

        staged_bad = os.path.join(stage_dir, live_bad)
        with open(staged_bad, "wb") as f:
            f.write(corrupt_payloads[live_bad])
        original_bytes[live_bad] = corrupt_payloads[live_bad]
        os.replace(staged_bad, os.path.join(dropzone, live_bad))

        live_final = normalized(live_tar)
        wait_until(
            lambda: os.path.isfile(os.path.join(curated, live_final))
                    and os.path.isfile(os.path.join(quarantine, live_bad)),
            message="Curator did not continuously process newly arriving archives",
        )
        assert proc.poll() is None, "Curator exited before SHUTDOWN appeared"

        staged_last = os.path.join(stage_dir, last_zip)
        make_zip(staged_last, *valid_payloads[last_zip])
        with open(staged_last, "rb") as f:
            original_bytes[last_zip] = f.read()
        os.replace(staged_last, os.path.join(dropzone, last_zip))
        open(os.path.join(dropzone, "SHUTDOWN"), "wb").close()

        last_final = normalized(last_zip)
        wait_until(
            lambda: os.path.isfile(os.path.join(curated, last_final))
                    and not os.path.exists(os.path.join(dropzone, "SHUTDOWN")),
            timeout=20,
            message="Curator did not process remaining archives and delete SHUTDOWN",
        )
        try:
            return_code = proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            raise AssertionError("Curator did not exit after processing SHUTDOWN")
        assert return_code == 0, f"Curator exited with nonzero status {return_code}"
        drain_events()

        expected_curated = {normalized(name) for name in valid_payloads}
        expected_quarantine = set(corrupt_payloads)
        assert set(os.listdir(curated)) == expected_curated, "Curated output names are incorrect or contain extra files"
        assert set(os.listdir(quarantine)) == expected_quarantine, "Quarantine names are incorrect or contain extra files"
        assert os.listdir(dropzone) == [], "Dropzone was not emptied after shutdown"

        for source_name, (member, payload) in valid_payloads.items():
            final_name = normalized(source_name)
            final_path = os.path.join(curated, final_name)
            with open(final_path, "rb") as f:
                assert f.read() == original_bytes[source_name], f"Archive bytes were not preserved for {source_name}"
            if final_name.endswith(".zip"):
                with zipfile.ZipFile(final_path, "r") as zf:
                    assert zf.testzip() is None, f"Output ZIP is corrupt: {final_name}"
                    assert zf.read(member) == payload, f"ZIP contents changed: {final_name}"
            else:
                with tarfile.open(final_path, "r:gz") as tf:
                    extracted = tf.extractfile(member)
                    assert extracted is not None and extracted.read() == payload, f"Tar contents changed: {final_name}"

        for source_name, payload in corrupt_payloads.items():
            with open(os.path.join(quarantine, source_name), "rb") as f:
                assert f.read() == payload, f"Corrupt archive was altered or incorrectly handled: {source_name}"

        for final_name in expected_curated:
            tmp_name = final_name + ".tmp"
            temp_arrivals = [e for e in events if e[2] == tmp_name and e[0] & (IN_CREATE | IN_MOVED_TO)]
            assert temp_arrivals, f"No temporary .tmp placement was observed for {final_name}"
            renames_from_tmp = {(cookie, name) for mask, cookie, name in events if mask & IN_MOVED_FROM and name == tmp_name}
            renames_to_final = {(cookie, name) for mask, cookie, name in events if mask & IN_MOVED_TO and name == final_name}
            assert any((cookie, final_name) in renames_to_final for cookie, _ in renames_from_tmp if cookie), \
                f"{final_name} was not atomically renamed from {tmp_name}"

        assert not any(name.endswith(".tmp") for name in os.listdir(curated)), "Temporary files remain in curated"
    finally:
        os.close(fd)
        if proc is not None and proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
        import shutil
        shutil.rmtree(stage_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
