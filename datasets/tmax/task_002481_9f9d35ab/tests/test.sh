#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import subprocess
import time


def wait_for(predicate, proc=None, timeout=8.0, message="condition not met"):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        if proc is not None and proc.poll() is not None:
            raise AssertionError(f"storage_dedup exited unexpectedly with status {proc.returncode}")
        try:
            if predicate():
                return
        except (FileNotFoundError, OSError) as exc:
            last_error = exc
        time.sleep(0.05)
    if last_error:
        raise AssertionError(f"{message}: {last_error}")
    raise AssertionError(message)


def uses_inotify(proc):
    fd_dir = f"/proc/{proc.pid}/fd"
    try:
        for fd in os.listdir(fd_dir):
            try:
                if "anon_inode:inotify" in os.readlink(os.path.join(fd_dir, fd)):
                    return True
            except OSError:
                pass
    except OSError:
        pass
    return False


def stop(proc):
    proc.terminate()
    try:
        proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=3)


def write_file(path, data):
    with open(path, "wb") as f:
        f.write(data)


def read_logs(path):
    with open(path, "r", encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]


def test_storage_dedup_executable_exists():
    executable = "/home/user/storage_dedup"
    assert os.path.exists(executable), f"Executable {executable} not found. Did you compile the C program?"
    assert os.access(executable, os.X_OK), f"{executable} is not executable."


def test_storage_dedup_original_behavior():
    watch_dir = "/home/user/watch_dir"
    archive_dir = "/home/user/archive_dir"
    config_file = "/home/user/config.txt"
    log_file = "/home/user/dedup.log"
    executable = "/home/user/storage_dedup"

    shutil.rmtree(watch_dir, ignore_errors=True)
    shutil.rmtree(archive_dir, ignore_errors=True)
    os.makedirs(watch_dir)
    os.makedirs(archive_dir)

    with open(config_file, "w") as f:
        f.write(f"WATCH_DIR={watch_dir}\n")
        f.write(f"ARCHIVE_DIR={archive_dir}\n")

    if os.path.lexists(log_file):
        os.remove(log_file)

    proc = subprocess.Popen([executable])
    try:
        wait_for(lambda: uses_inotify(proc), proc, message="program did not establish an inotify instance")

        write_file(os.path.join(watch_dir, "test1.bin"), b"AAA")
        test1_watch = os.path.join(watch_dir, "test1.bin")
        test1_archive = os.path.join(archive_dir, "test1.bin")
        wait_for(lambda: os.path.islink(test1_watch) and os.path.exists(test1_archive), proc,
                 message="test1.bin was not processed")

        write_file(os.path.join(watch_dir, "test2.bin"), b"AAA")
        test2_watch = os.path.join(watch_dir, "test2.bin")
        wait_for(lambda: os.path.exists(test2_watch) and not os.path.islink(test2_watch), proc,
                 message="test2.bin was not processed")

        write_file(os.path.join(watch_dir, "test3.bin"), b"BBB")
        test3_watch = os.path.join(watch_dir, "test3.bin")
        test3_archive = os.path.join(archive_dir, "test3.bin")
        wait_for(lambda: os.path.islink(test3_watch) and os.path.exists(test3_archive), proc,
                 message="test3.bin was not processed")

        expected_logs = [
            "NEW: test1.bin -> test1.bin",
            "DUPLICATE: test2.bin -> test1.bin",
            "NEW: test3.bin -> test3.bin",
        ]
        wait_for(lambda: os.path.exists(log_file) and all(x in read_logs(log_file) for x in expected_logs),
                 proc, message="expected original log entries were not written")
    finally:
        stop(proc)

    assert os.path.islink(test1_watch), "test1.bin in watch_dir should be a symlink for a new file."
    assert os.readlink(test1_watch) == test1_archive, "test1.bin symlink points to the wrong target."
    assert os.path.exists(test1_archive), "test1.bin was not moved to the archive_dir."

    assert os.path.exists(test2_watch), "test2.bin is missing in watch_dir."
    assert not os.path.islink(test2_watch), "test2.bin should be a hard link, not a symlink."
    assert os.stat(test2_watch).st_ino == os.stat(test1_archive).st_ino, "test2.bin is not a hard link to test1.bin in the archive."

    assert os.path.islink(test3_watch), "test3.bin in watch_dir should be a symlink for a new file."
    assert os.readlink(test3_watch) == test3_archive, "test3.bin symlink points to the wrong target."
    assert os.path.exists(test3_archive), "test3.bin was not moved to the archive_dir."

    assert os.path.exists(log_file), "/home/user/dedup.log was not created."
    log_content = read_logs(log_file)
    expected_logs = [
        "NEW: test1.bin -> test1.bin",
        "DUPLICATE: test2.bin -> test1.bin",
        "NEW: test3.bin -> test3.bin",
    ]
    for expected in expected_logs:
        assert expected in log_content, f"Expected log line '{expected}' not found in {log_file}."


def test_random_binary_configuration_and_ongoing_behavior():
    token = secrets.token_hex(8)
    base = os.path.join("/home/user", f"dedup_case_{token}")
    watch_dir = os.path.join(base, f"watch_{secrets.token_hex(4)}")
    archive_dir = os.path.join(base, f"archive_{secrets.token_hex(4)}")
    config_file = "/home/user/config.txt"
    log_file = "/home/user/dedup.log"
    executable = "/home/user/storage_dedup"

    os.makedirs(watch_dir)
    os.makedirs(archive_dir)

    new_name = f"new_{secrets.token_hex(6)}.bin"
    duplicate_name = f"copy_{secrets.token_hex(6)}.dat"
    existing_name = f"existing_{secrets.token_hex(6)}.blob"
    existing_copy_name = f"incoming_{secrets.token_hex(6)}.raw"
    later_name = f"later_{secrets.token_hex(6)}.bin"
    directory_name = f"directory_{secrets.token_hex(4)}"

    new_data = b"\x00\xff" + secrets.token_bytes(4097) + b"\x00"
    existing_data = b"\x7fELF\x00" + secrets.token_bytes(3073)
    later_data = new_data[:-1] + bytes([new_data[-1] ^ 0x5A])
    while existing_data == new_data or later_data in (new_data, existing_data):
        existing_data = secrets.token_bytes(3080)
        later_data = secrets.token_bytes(4099)

    existing_archive = os.path.join(archive_dir, existing_name)
    write_file(existing_archive, existing_data)

    with open(config_file, "w") as f:
        f.write(f"WATCH_DIR={watch_dir}\n")
        f.write(f"ARCHIVE_DIR={archive_dir}\n")
    if os.path.lexists(log_file):
        os.remove(log_file)

    proc = subprocess.Popen([executable])
    try:
        wait_for(lambda: uses_inotify(proc), proc, message="program did not use inotify for the randomized watch directory")

        os.mkdir(os.path.join(watch_dir, directory_name))

        new_watch = os.path.join(watch_dir, new_name)
        new_archive = os.path.join(archive_dir, new_name)
        write_file(new_watch, new_data)
        wait_for(lambda: os.path.islink(new_watch) and os.path.exists(new_archive), proc,
                 message="random binary new file was not archived")
        assert os.readlink(new_watch) == new_archive
        assert open(new_archive, "rb").read() == new_data

        duplicate_watch = os.path.join(watch_dir, duplicate_name)
        write_file(duplicate_watch, new_data)
        wait_for(lambda: os.path.exists(duplicate_watch) and not os.path.islink(duplicate_watch), proc,
                 message="random duplicate was not hard-linked")
        assert os.stat(duplicate_watch).st_dev == os.stat(new_archive).st_dev
        assert os.stat(duplicate_watch).st_ino == os.stat(new_archive).st_ino
        assert not os.path.lexists(os.path.join(archive_dir, duplicate_name))

        existing_copy_watch = os.path.join(watch_dir, existing_copy_name)
        write_file(existing_copy_watch, existing_data)
        wait_for(lambda: os.path.exists(existing_copy_watch) and not os.path.islink(existing_copy_watch), proc,
                 message="duplicate of a pre-existing archive file was not hard-linked")
        assert os.stat(existing_copy_watch).st_ino == os.stat(existing_archive).st_ino
        assert os.stat(existing_copy_watch).st_dev == os.stat(existing_archive).st_dev
        assert not os.path.lexists(os.path.join(archive_dir, existing_copy_name))

        # Exercise the same long-running process again after earlier events.
        time.sleep(0.4)
        later_watch = os.path.join(watch_dir, later_name)
        later_archive = os.path.join(archive_dir, later_name)
        write_file(later_watch, later_data)
        wait_for(lambda: os.path.islink(later_watch) and os.path.exists(later_archive), proc,
                 message="daemon did not continue processing later events")
        assert os.readlink(later_watch) == later_archive
        assert open(later_archive, "rb").read() == later_data

        expected = [
            f"NEW: {new_name} -> {new_name}",
            f"DUPLICATE: {duplicate_name} -> {new_name}",
            f"DUPLICATE: {existing_copy_name} -> {existing_name}",
            f"NEW: {later_name} -> {later_name}",
        ]
        wait_for(lambda: os.path.exists(log_file) and all(line in read_logs(log_file) for line in expected),
                 proc, message="randomized log entries were not written")
        assert os.path.isdir(os.path.join(watch_dir, directory_name)), "watch subdirectory should not be processed"
    finally:
        stop(proc)
        shutil.rmtree(base, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
