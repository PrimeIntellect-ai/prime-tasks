#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import pathlib
import shutil
import stat
import subprocess
import uuid

BASE = pathlib.Path("/home/user/microservices")


def test_crashed_txt_exists_and_correct():
    path = BASE / "crashed.txt"
    assert path.is_file(), f"File {path} is missing."
    lines = [line.strip() for line in path.read_text().splitlines() if line.strip()]
    assert set(lines) == {"db_backend", "payment_gateway"}, (
        f"Contents of {path} do not match the expected crashed services. Found: {lines}"
    )


def test_auto_extract_exp_exists():
    path = BASE / "auto_extract.exp"
    assert path.is_file(), f"Expect script {path} is missing."
    content = path.read_text()
    assert "secret_vault" in content, (
        f"Expect script {path} does not seem to contain the correct password."
    )


def test_restore_manager_cpp_exists():
    path = BASE / "restore_manager.cpp"
    assert path.is_file(), f"C++ source file {path} is missing."


def test_restore_manager_executable_exists():
    path = BASE / "restore_manager"
    assert path.is_file(), f"Compiled executable {path} is missing."
    assert os.access(path, os.X_OK), f"File {path} is not executable."
    with path.open("rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {path} is not a compiled executable."


def test_recovery_log_exists_and_correct():
    path = BASE / "recovery.log"
    assert path.is_file(), f"Recovery log {path} is missing."
    lines = [line.strip() for line in path.read_text().splitlines() if line.strip()]
    expected_lines = {
        "RESTORED db_backend TO /home/user/microservices/vols/db",
        "RESTORED payment_gateway TO /home/user/microservices/vols/pay",
    }
    assert set(lines) == expected_lines, (
        f"Contents of {path} do not match expected recovery log entries. Found: {lines}"
    )


def test_restored_data_files():
    db_restored = BASE / "vols/db/restored_data.txt"
    pay_restored = BASE / "vols/pay/restored_data.txt"
    auth_restored = BASE / "vols/auth/restored_data.txt"
    assert db_restored.is_file(), f"Expected restored data file missing: {db_restored}"
    assert pay_restored.is_file(), f"Expected restored data file missing: {pay_restored}"
    assert not auth_restored.exists(), (
        f"File {auth_restored} should not exist (auth service did not crash)."
    )


def _watch_open(path):
    libc = ctypes.CDLL(None, use_errno=True)
    libc.inotify_init1.argtypes = [ctypes.c_int]
    libc.inotify_init1.restype = ctypes.c_int
    libc.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
    libc.inotify_add_watch.restype = ctypes.c_int
    fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
    assert fd >= 0, "Could not initialize inotify."
    wd = libc.inotify_add_watch(fd, os.fsencode(path), 0x20)  # IN_OPEN
    assert wd >= 0, f"Could not watch {path}."
    return fd


def _saw_event(fd):
    try:
        return bool(os.read(fd, 65536))
    except BlockingIOError:
        return False
    finally:
        os.close(fd)


def _prepare_fixture(tag):
    first = f"orders_{tag}"
    second = f"ledger_{tag}"
    decoy = f"healthy_{tag}"
    root = BASE / f"verify_{tag}"
    destinations = [root / "one", root / "two"]
    for destination in destinations:
        destination.mkdir(parents=True, exist_ok=True)
    backups = [root / "first.backup", root / "second.backup"]

    (BASE / "crashed.txt").write_text(f"{first}\n{second}\n")
    (BASE / "volumes.fstab").write_text(
        f"{first} {backups[0]} {destinations[0]}\n"
        f"{second} {backups[1]} {destinations[1]}\n"
        f"{decoy} {root / 'decoy.backup'} {root / 'decoy'}\n"
    )
    log = BASE / "recovery.log"
    if log.exists():
        log.unlink()
    return [first, second], backups, destinations, root / "decoy"


def _run_manager(executable, probe_log):
    tag = uuid.uuid4().hex
    services, backups, destinations, decoy = _prepare_fixture(tag)
    if probe_log.exists():
        probe_log.unlink()

    expect_script = BASE / "auto_extract.exp"
    watch_fd = _watch_open(expect_script)
    result = subprocess.run(
        [str(executable)], text=True, capture_output=True, timeout=20
    )
    opened_expect = _saw_event(watch_fd)

    assert result.returncode == 0, (
        f"Manager {executable} failed: stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert opened_expect, f"Manager {executable} did not execute auto_extract.exp."

    log = BASE / "recovery.log"
    assert log.is_file(), "Manager did not create recovery.log."
    actual_log = {line.strip() for line in log.read_text().splitlines() if line.strip()}
    expected_log = {
        f"RESTORED {services[i]} TO {destinations[i]}" for i in range(2)
    }
    assert actual_log == expected_log, (
        f"Manager produced incorrect dynamic recovery entries: {actual_log}"
    )

    for destination in destinations:
        assert (destination / "restored_data.txt").is_file(), (
            f"Manager did not restore dynamic destination {destination}"
        )
    assert not (decoy / "restored_data.txt").exists(), (
        "Manager restored a service that was not listed as crashed."
    )

    assert probe_log.is_file(), "The extraction tool was not invoked."
    invocations = {
        line.strip() for line in probe_log.read_text().splitlines() if line.strip()
    }
    expected_invocations = {
        f"{backups[i]}|{destinations[i]}" for i in range(2)
    }
    assert invocations == expected_invocations, (
        f"Incorrect extraction invocations: {invocations}"
    )


def test_expect_and_manager_pipeline_on_dynamic_inputs(tmp_path):
    expect_script = BASE / "auto_extract.exp"
    extract_script = BASE / "extract_backup.sh"

    # Exercise the submitted Expect program against the original interactive tool.
    standalone_dest = tmp_path / "expect_destination"
    standalone_dest.mkdir()
    result = subprocess.run(
        ["expect", str(expect_script), str(tmp_path / "novel.backup"), str(standalone_dest)],
        text=True,
        capture_output=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"Expect script failed: stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert (standalone_dest / "restored_data.txt").is_file(), (
        "Expect script did not successfully answer the password prompt."
    )

    # Compile the submitted source independently so a placeholder source cannot pass.
    compiled = tmp_path / "manager_from_source"
    build = subprocess.run(
        ["g++", str(BASE / "restore_manager.cpp"), "-o", str(compiled)],
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert build.returncode == 0, (
        f"restore_manager.cpp does not compile: stdout={build.stdout!r}, stderr={build.stderr!r}"
    )

    # Use a compatible instrumented extraction tool to prove each manager run
    # actually dispatches through the submitted Expect script.
    original_bytes = extract_script.read_bytes()
    original_mode = stat.S_IMODE(extract_script.stat().st_mode)
    probe_log = tmp_path / "extract_invocations.log"
    probe = f'''#!/bin/bash
read -p "Enter password: " pass
if [ "$pass" = "secret_vault" ]; then
    printf '%s|%s\\n' "$1" "$2" >> "{probe_log}"
    echo "Restored files from $1 to $2"
    touch "$2/restored_data.txt"
    exit 0
else
    echo "Access denied."
    exit 1
fi
'''
    try:
        extract_script.write_text(probe)
        extract_script.chmod(0o755)
        _run_manager(BASE / "restore_manager", probe_log)
        _run_manager(compiled, probe_log)
    finally:
        extract_script.write_bytes(original_bytes)
        extract_script.chmod(original_mode)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
