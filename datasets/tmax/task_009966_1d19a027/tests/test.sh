#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import glob
import os
import resource
import shutil
import struct
import subprocess
import tempfile


def test_archiver_cpp_exists():
    assert os.path.isfile("/home/user/archiver.cpp"), "The C++ source file /home/user/archiver.cpp is missing."


def test_archive_dat_exists_and_content():
    archive_path = "/home/user/archive.dat"
    assert os.path.isfile(archive_path), f"The archive file {archive_path} is missing."

    with open(archive_path, "r") as f:
        content = f.read()

    expected_content = (
        "=== app.log ===\n"
        "FATAL Out of memory exception in thread 1\n"
        "FATAL Process crashed\n"
        "=== sys.log ===\n"
        "FATAL Disk /dev/sda1 failure\n"
    )

    assert content == expected_content, f"The content of {archive_path} does not match the expected format and filtered lines."


def test_processed_log_files_exist():
    expected_files = [
        "/home/user/logs/app.log.processed",
        "/home/user/logs/auth.log.processed",
        "/home/user/logs/sys.log.processed"
    ]
    for file_path in expected_files:
        assert os.path.isfile(file_path), f"The processed log file {file_path} is missing."


def test_no_unprocessed_log_files():
    unprocessed_logs = glob.glob("/home/user/logs/*.log")
    assert len(unprocessed_logs) == 0, f"Found unprocessed log files: {unprocessed_logs}. They should have been renamed to .log.processed."


def test_z_compile_and_execute_on_fresh_inputs():
    source = "/home/user/archiver.cpp"
    binary = "/tmp/archiver_verifier_bin"
    compile_result = subprocess.run(
        ["g++", "-std=c++17", source, "-o", binary],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert compile_result.returncode == 0, "archiver.cpp did not compile with g++ -std=c++17:\n" + compile_result.stderr

    logs_path = "/home/user/logs"
    config_path = "/home/user/config.txt"
    archive_path = "/home/user/archive.dat"
    backup_root = tempfile.mkdtemp(prefix="archiver-state-")
    output_dir = tempfile.mkdtemp(prefix="archiver-output-")
    dynamic_archive = os.path.join(output_dir, "archive.custom")
    backup_logs = os.path.join(backup_root, "logs")
    shutil.copytree(logs_path, backup_logs)
    with open(config_path, "rb") as f:
        saved_config = f.read()
    saved_archive = None
    if os.path.isfile(archive_path):
        with open(archive_path, "rb") as f:
            saved_archive = f.read()

    inotify_fd = -1
    try:
        shutil.rmtree(logs_path)
        os.makedirs(logs_path)

        fixtures = {
            "a.log": b"ordinary line\nNEEDLE alpha\nNEEDLE twice NEEDLE\n",
            "aa.log": b"prefix NEEDLE suffix\n",
            "none.log": b"nothing relevant here\n",
            "z.log": b"NEEDLE zed\n",
        }
        for name, data in fixtures.items():
            with open(os.path.join(logs_path, name), "wb") as f:
                f.write(data)

        # This no-match file is larger than the process memory allowance, so an
        # implementation which loads every input file wholesale cannot pass.
        big_path = os.path.join(logs_path, "big.log")
        line = b"ordinary nonmatching data " + b"x" * 998 + b"\n"
        with open(big_path, "wb") as f:
            for _ in range(48 * 1024):
                f.write(line)

        with open(os.path.join(logs_path, "keep.txt"), "wb") as f:
            f.write(b"must not be renamed\n")

        # Reverse the config line order and use a fresh destination/filter to
        # ensure the named keys are actually interpreted.
        with open(config_path, "w", newline="") as f:
            f.write("FILTER_KEY=NEEDLE\n")
            f.write(f"ARCHIVE_PATH={dynamic_archive}\n")

        libc = ctypes.CDLL(None, use_errno=True)
        libc.inotify_init1.argtypes = [ctypes.c_int]
        libc.inotify_init1.restype = ctypes.c_int
        libc.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
        libc.inotify_add_watch.restype = ctypes.c_int
        IN_CLOSE_WRITE = 0x00000008
        IN_MOVED_TO = 0x00000080
        IN_CREATE = 0x00000100
        inotify_fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
        assert inotify_fd >= 0, "Could not initialize inotify"
        wd = libc.inotify_add_watch(
            inotify_fd,
            output_dir.encode(),
            IN_CLOSE_WRITE | IN_MOVED_TO | IN_CREATE,
        )
        assert wd >= 0, "Could not monitor the archive output directory"

        def limit_memory():
            limit = 32 * 1024 * 1024
            resource.setrlimit(resource.RLIMIT_AS, (limit, limit))

        run_result = subprocess.run(
            [binary],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=45,
            preexec_fn=limit_memory,
        )
        assert run_result.returncode == 0, (
            "The compiled archiver failed on fresh inputs.\nstdout:\n"
            + run_result.stdout
            + "\nstderr:\n"
            + run_result.stderr
        )

        events = []
        while True:
            try:
                data = os.read(inotify_fd, 65536)
            except BlockingIOError:
                break
            if not data:
                break
            offset = 0
            while offset < len(data):
                event_wd, mask, cookie, name_len = struct.unpack_from("iIII", data, offset)
                offset += 16
                raw_name = data[offset:offset + name_len]
                offset += name_len
                name = raw_name.split(b"\0", 1)[0].decode(errors="replace")
                events.append((name, mask))

        assert os.path.isfile(dynamic_archive), "The configured archive path was not created"
        with open(dynamic_archive, "rb") as f:
            actual = f.read()
        expected = (
            b"=== a.log ===\n"
            b"NEEDLE alpha\n"
            b"NEEDLE twice NEEDLE\n"
            b"=== aa.log ===\n"
            b"prefix NEEDLE suffix\n"
            b"=== z.log ===\n"
            b"NEEDLE zed\n"
        )
        assert actual == expected, "Fresh inputs were not filtered, ordered, or formatted correctly"

        assert any(name == "archive.custom" and (mask & IN_MOVED_TO) for name, mask in events), (
            "The final archive was not installed by an atomic rename from a temporary file"
        )
        assert sorted(os.listdir(output_dir)) == ["archive.custom"], "Temporary archive files were left behind"

        for name, original in fixtures.items():
            processed = os.path.join(logs_path, name + ".processed")
            assert os.path.isfile(processed), f"{name} was not renamed after successful archiving"
            with open(processed, "rb") as f:
                assert f.read() == original, f"Renaming changed the contents of {name}"
        assert os.path.isfile(big_path + ".processed"), "The large .log file was not renamed"
        assert not glob.glob(os.path.join(logs_path, "*.log")), "Some fresh .log inputs were left unprocessed"
        assert os.path.isfile(os.path.join(logs_path, "keep.txt")), "A non-.log file was incorrectly renamed"
    finally:
        if inotify_fd >= 0:
            os.close(inotify_fd)
        if os.path.exists(logs_path):
            shutil.rmtree(logs_path)
        shutil.copytree(backup_logs, logs_path)
        with open(config_path, "wb") as f:
            f.write(saved_config)
        if saved_archive is not None:
            with open(archive_path, "wb") as f:
                f.write(saved_archive)
        elif os.path.exists(archive_path):
            os.remove(archive_path)
        shutil.rmtree(output_dir, ignore_errors=True)
        shutil.rmtree(backup_root, ignore_errors=True)
        if os.path.exists(binary):
            os.remove(binary)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
