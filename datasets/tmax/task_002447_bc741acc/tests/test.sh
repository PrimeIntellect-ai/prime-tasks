#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import tarfile
import time
import uuid


def test_directories_exist():
    """Verify that incoming and outgoing directories exist."""
    assert os.path.isdir("/home/user/incoming"), "/home/user/incoming directory does not exist."
    assert os.path.isdir("/home/user/outgoing"), "/home/user/outgoing directory does not exist."


def test_script_exists_and_executable():
    """Verify that the organizer script exists and is executable."""
    script_path = "/home/user/organizer.sh"
    assert os.path.isfile(script_path), f"{script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."


def test_incoming_empty():
    """Verify that incoming directory is empty of .tar.gz files."""
    incoming_files = os.listdir("/home/user/incoming")
    tar_gz_files = [f for f in incoming_files if f.endswith(".tar.gz")]
    assert len(tar_gz_files) == 0, f"/home/user/incoming still contains .tar.gz files: {tar_gz_files}"


def test_log_file_contents():
    """Verify that the log file contains the correct entries."""
    log_path = "/home/user/organizer.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = {
        "PROCESSED: legacy_code_A.tar.gz | CONVERTED_FILES: 2",
        "PROCESSED: legacy_code_B.tar.gz | CONVERTED_FILES: 1"
    }

    actual_lines_set = set(lines)
    for expected in expected_lines:
        assert expected in actual_lines_set, f"Expected log entry '{expected}' not found in {log_path}."


def test_outgoing_archives():
    """Verify the outgoing archives exist and contain the correctly converted UTF-8 files."""
    outgoing_dir = "/home/user/outgoing"
    archive_a = os.path.join(outgoing_dir, "legacy_code_A.tar.gz")
    archive_b = os.path.join(outgoing_dir, "legacy_code_B.tar.gz")

    assert os.path.isfile(archive_a), f"Archive {archive_a} is missing."
    assert os.path.isfile(archive_b), f"Archive {archive_b} is missing."

    with tarfile.open(archive_a, "r:gz") as tar:
        members = tar.getnames()
        assert "projectA/main.src" in members, "projectA/main.src missing in legacy_code_A.tar.gz"
        assert "projectA/utils/helper.src" in members, "projectA/utils/helper.src missing in legacy_code_A.tar.gz"
        assert "projectA/readme.txt" in members, "projectA/readme.txt missing in legacy_code_A.tar.gz"

        main_src = tar.extractfile("projectA/main.src").read()
        assert main_src == b"caf\xc3\xa9\n", "projectA/main.src was not correctly converted to UTF-8."

        helper_src = tar.extractfile("projectA/utils/helper.src").read()
        assert helper_src == b"r\xc3\xa9sum\xc3\xa9\n", "projectA/utils/helper.src was not correctly converted to UTF-8."

        readme = tar.extractfile("projectA/readme.txt").read()
        assert readme == b"README\n", "projectA/readme.txt was modified but should have been left untouched."

    with tarfile.open(archive_b, "r:gz") as tar:
        members = tar.getnames()
        assert "moduleB/app.src" in members, "moduleB/app.src missing in legacy_code_B.tar.gz"

        app_src = tar.extractfile("moduleB/app.src").read()
        assert app_src == b"ni\xc3\xb1o\n", "moduleB/app.src was not correctly converted to UTF-8."


def running_organizer_pids():
    """Return live Bash processes whose command line identifies organizer.sh."""
    found = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            with open(f"/proc/{name}/cmdline", "rb") as f:
                args = [a.decode("utf-8", "replace") for a in f.read().split(b"\0") if a]
            exe = os.path.basename(os.readlink(f"/proc/{name}/exe"))
            cwd = os.readlink(f"/proc/{name}/cwd")
        except (FileNotFoundError, PermissionError, ProcessLookupError, OSError):
            continue
        if exe not in ("bash", "bash.static"):
            continue
        identified = False
        for arg in args[1:]:
            if arg == "/home/user/organizer.sh":
                identified = True
                break
            if arg.endswith("organizer.sh"):
                candidate = arg if os.path.isabs(arg) else os.path.join(cwd, arg)
                if os.path.realpath(candidate) == "/home/user/organizer.sh":
                    identified = True
                    break
            if "/home/user/organizer.sh" in arg:
                identified = True
                break
        if identified:
            found.add(int(name))
    return found


def add_directory(tar, name):
    info = tarfile.TarInfo(name)
    info.type = tarfile.DIRTYPE
    info.mode = 0o755
    info.mtime = 1700000000
    tar.addfile(info)


def add_file(tar, name, data):
    info = tarfile.TarInfo(name)
    info.size = len(data)
    info.mode = 0o644
    info.mtime = 1700000000
    tar.addfile(info, io.BytesIO(data))


def test_live_daemon_processes_fresh_archive():
    """Submit an unpredictable archive and verify the live daemon performs the full workflow."""
    initial_pids = running_organizer_pids()
    assert initial_pids, "/home/user/organizer.sh is not running as a Bash background process."

    token = uuid.uuid4().hex
    filename = f"verifier_probe_{token}.tar.gz"
    incoming_path = os.path.join("/home/user/incoming", filename)
    outgoing_path = os.path.join("/home/user/outgoing", filename)
    build_path = os.path.join("/tmp", filename)

    legacy_files = {
        f"drop_{token}/root.src": b"fresh caf\xe9 " + token.encode("ascii") + b"\n",
        f"drop_{token}/lib/worker.src": b"ni\xf1o and r\xe9sum\xe9\n",
        f"drop_{token}/lib/deeper/value.src": b"price \xa3 and \xfcber\n",
    }
    untouched_files = {
        f"drop_{token}/README.txt": b"untouched README\n",
        f"drop_{token}/lib/payload.bin": b"\x00\xff\x10not-a-source\n",
    }
    directories = [
        f"drop_{token}",
        f"drop_{token}/lib",
        f"drop_{token}/lib/deeper",
    ]

    with tarfile.open(build_path, "w:gz") as tar:
        for directory in directories:
            add_directory(tar, directory)
        for name, data in {**legacy_files, **untouched_files}.items():
            add_file(tar, name, data)

    assert not os.path.exists(outgoing_path), "Fresh probe name unexpectedly already exists in outgoing."
    os.replace(build_path, incoming_path)

    expected_log = f"PROCESSED: {filename} | CONVERTED_FILES: {len(legacy_files)}"
    deadline = time.monotonic() + 20
    last_error = None
    while time.monotonic() < deadline:
        try:
            log_ok = False
            if os.path.isfile("/home/user/organizer.log"):
                with open("/home/user/organizer.log", "r", encoding="utf-8") as f:
                    log_ok = expected_log in {line.strip() for line in f if line.strip()}
            if os.path.isfile(outgoing_path) and not os.path.exists(incoming_path) and log_ok:
                with tarfile.open(outgoing_path, "r:gz") as tar:
                    tar.getmembers()
                break
        except (OSError, tarfile.TarError) as exc:
            last_error = exc
        time.sleep(0.25)
    else:
        raise AssertionError(
            f"Daemon did not process, log, and delete fresh archive within 20 seconds; last error: {last_error}"
        )

    surviving_pids = running_organizer_pids()
    assert initial_pids & surviving_pids, "The organizer daemon did not remain running after processing."
    assert not os.path.exists(incoming_path), "The fresh input archive was not deleted."

    with open("/home/user/organizer.log", "r", encoding="utf-8") as f:
        log_lines = [line.strip() for line in f if line.strip()]
    assert expected_log in log_lines, f"Expected fresh log entry '{expected_log}' was not written."

    expected_names = set(directories) | set(legacy_files) | set(untouched_files)
    with tarfile.open(outgoing_path, "r:gz") as tar:
        members = tar.getmembers()
        assert {m.name for m in members} == expected_names, (
            "Fresh output archive did not preserve the input archive's exact internal structure."
        )
        by_name = {m.name: m for m in members}
        for directory in directories:
            assert by_name[directory].isdir(), f"{directory} is no longer a directory."
        for name, original in legacy_files.items():
            member = by_name[name]
            assert member.isfile(), f"{name} is no longer a regular file."
            actual = tar.extractfile(member).read()
            expected = original.decode("iso-8859-1").encode("utf-8")
            assert actual == expected, f"{name} was not converted from ISO-8859-1 to UTF-8."
        for name, expected in untouched_files.items():
            member = by_name[name]
            assert member.isfile(), f"{name} is no longer a regular file."
            actual = tar.extractfile(member).read()
            assert actual == expected, f"Non-.src file {name} was modified."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
