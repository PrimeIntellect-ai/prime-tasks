#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'PY' > /tmp/test_original_state.py
import os
import tarfile


def test_skipped_links_file():
    skipped_links_path = "/home/user/skipped_links.txt"
    assert os.path.exists(skipped_links_path), f"File {skipped_links_path} does not exist."

    with open(skipped_links_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_links = [
        "/home/user/configs/app_beta/loop1.lnk",
        "/home/user/configs/app_beta/loop2.lnk",
        "/home/user/configs/app_gamma/self_loop.lnk",
    ]
    assert lines == expected_links, f"Expected skipped links {expected_links}, but got {lines}."


def test_app_beta_archive():
    archive_path = "/home/user/archives/app_beta.tar.gz"
    assert os.path.exists(archive_path), f"Archive {archive_path} does not exist."

    with tarfile.open(archive_path, "r:gz") as tar:
        members = tar.getmembers()
        file_names = {os.path.basename(m.name) for m in members if m.isfile()}

        assert "config.ini" in file_names, "config.ini missing from app_beta.tar.gz"
        assert "valid_link.ini" in file_names, "valid_link.ini missing from app_beta.tar.gz"
        assert "loop1.lnk" not in file_names, "loop1.lnk should not be in app_beta.tar.gz"
        assert "loop2.lnk" not in file_names, "loop2.lnk should not be in app_beta.tar.gz"

        valid_link_member = next(m for m in members if os.path.basename(m.name) == "valid_link.ini")
        assert valid_link_member.isfile(), "valid_link.ini must be stored as a regular file, not a symlink."
        content = tar.extractfile(valid_link_member).read().decode("utf-8").strip()
        assert content == "beta_setting=2", f"valid_link.ini content incorrect: {content}"


def test_app_gamma_archive():
    archive_path = "/home/user/archives/app_gamma.tar.gz"
    assert os.path.exists(archive_path), f"Archive {archive_path} does not exist."

    with tarfile.open(archive_path, "r:gz") as tar:
        members = tar.getmembers()
        file_names = {os.path.basename(m.name) for m in members if m.isfile()}

        assert "settings.conf" in file_names, "settings.conf missing from app_gamma.tar.gz"
        assert "cross_link.ini" in file_names, "cross_link.ini missing from app_gamma.tar.gz"
        assert "self_loop.lnk" not in file_names, "self_loop.lnk should not be in app_gamma.tar.gz"

        cross_link_member = next(m for m in members if os.path.basename(m.name) == "cross_link.ini")
        assert cross_link_member.isfile(), "cross_link.ini must be stored as a regular file, not a symlink."
        content = tar.extractfile(cross_link_member).read().decode("utf-8").strip()
        assert content == "beta_setting=2", f"cross_link.ini content incorrect: {content}"


def test_fcntl_used():
    script_path = "/home/user/archive_configs.py"
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    with open(script_path, "r") as f:
        content = f.read()
    assert "fcntl" in content, "The script must use fcntl for file locking as requested."
PY

cat << 'PY' > /tmp/test_dynamic_execution.py
import fcntl
import os
import posixpath
import secrets
import shutil
import subprocess
import sys
import tarfile
import time
from pathlib import Path

SCRIPT = Path("/home/user/archive_configs.py")
LOG = Path("/home/user/backup.log")
ARCHIVES = Path("/home/user/archives")
SKIPPED = Path("/home/user/skipped_links.txt")
CONFIGS = Path("/home/user/configs")

assert SCRIPT.is_file(), f"Required script does not exist: {SCRIPT}"
assert not SCRIPT.is_symlink(), "archive_configs.py must be a real script, not a symlink"

nonce = secrets.token_hex(8)
name_a = f"runtime_{nonce}_one"
name_b = f"runtime_{nonce}_two"
name_success = f"runtime_{nonce}_success"
name_other = f"runtime_{nonce}_other"
target_a = CONFIGS / name_a
target_b = CONFIGS / name_b
success_target = CONFIGS / name_success
other_target = CONFIGS / name_other

for path in (target_a, target_b, success_target, other_target):
    shutil.rmtree(path, ignore_errors=True)

target_a.mkdir(parents=True)
(target_a / "nested").mkdir()
target_b.mkdir(parents=True)
success_target.mkdir(parents=True)
other_target.mkdir(parents=True)

main_data = f"main-{secrets.token_hex(20)}\n"
settings_data = f"settings-{secrets.token_hex(20)}\n"
final_locked_data = f"locked-final-{secrets.token_hex(20)}\n"
transient_locked_data = f"LOCKED-TRANSIENT-{secrets.token_hex(20)}\n"

# Create this first and give it a sorting-friendly name so a normal traversal
# reaches the lock probe promptly.
locked_path = target_a / "000_locked.conf"
locked_path.write_text("initial data that must not be archived\n")
(target_a / "nested" / "main.conf").write_text(main_data)
(target_b / "settings.conf").write_text(settings_data)
(success_target / "ignored.conf").write_text("success must not be archived\n")
(other_target / "ignored.conf").write_text("wrong reason must not be archived\n")

os.symlink(str(target_a / "nested" / "main.conf"), target_a / "valid_alias.conf")
os.symlink(str(target_a / "cycle_two.lnk"), target_a / "cycle_one.lnk")
os.symlink(str(target_a / "cycle_one.lnk"), target_a / "cycle_two.lnk")
os.symlink(str(target_a / "nested" / "main.conf"), target_b / "cross_alias.conf")
os.symlink(str(target_b / "self_loop.lnk"), target_b / "self_loop.lnk")

LOG.write_text(
    f"""[runtime] JOB A
TARGET: {success_target}
STATUS: SUCCESS
--
[runtime] JOB B
TARGET: {target_a}
STATUS: FAILED
REASON: SYMLINK_LOOP
--
[runtime] JOB C
TARGET: {other_target}
STATUS: FAILED
REASON: PERMISSION_DENIED
--
[runtime] JOB D
TARGET: {target_b}
STATUS: FAILED
REASON: SYMLINK_LOOP
"""
)

ARCHIVES.mkdir(parents=True, exist_ok=True)
for child in ARCHIVES.iterdir():
    if child.is_dir() and not child.is_symlink():
        shutil.rmtree(child)
    else:
        child.unlink()
if SKIPPED.exists() or SKIPPED.is_symlink():
    SKIPPED.unlink()

# An exclusive holder writes a transient value and retains the lock. The
# submitted script must appear in /proc/locks waiting for a shared flock on
# this exact inode before the holder writes the final value and unlocks it.
locker_code = r'''
import fcntl, os, pathlib, sys, time
p = sys.argv[1]
ready = pathlib.Path(sys.argv[2])
release = pathlib.Path(sys.argv[3])
transient = sys.argv[4]
final = sys.argv[5]
with open(p, "r+b", buffering=0) as f:
    fcntl.flock(f.fileno(), fcntl.LOCK_EX)
    f.seek(0); f.truncate(); f.write(transient.encode()); os.fsync(f.fileno())
    ready.write_text("ready")
    while not release.exists():
        time.sleep(0.02)
    f.seek(0); f.truncate(); f.write(final.encode()); os.fsync(f.fileno())
    fcntl.flock(f.fileno(), fcntl.LOCK_UN)
'''
ready = Path(f"/tmp/archive_ready_{nonce}")
release = Path(f"/tmp/archive_release_{nonce}")
locker = subprocess.Popen([
    sys.executable, "-c", locker_code, str(locked_path), str(ready),
    str(release), transient_locked_data, final_locked_data,
])
runner = None
try:
    deadline = time.time() + 5
    while not ready.exists() and time.time() < deadline:
        assert locker.poll() is None, "lock-holder process exited unexpectedly"
        time.sleep(0.02)
    assert ready.exists(), "could not establish the verifier's exclusive lock"

    runner = subprocess.Popen([sys.executable, str(SCRIPT)], cwd="/home/user")
    inode = locked_path.stat().st_ino
    saw_waiting_shared_lock = False
    deadline = time.time() + 8
    while time.time() < deadline:
        if runner.poll() is not None:
            break
        try:
            lock_lines = Path("/proc/locks").read_text().splitlines()
        except OSError:
            lock_lines = []
        for line in lock_lines:
            fields = line.replace("->", " -> ").split()
            if ("->" in fields and "FLOCK" in fields and "READ" in fields
                    and str(runner.pid) in fields
                    and f" {inode} 0 EOF" in line):
                saw_waiting_shared_lock = True
                break
        if saw_waiting_shared_lock:
            break
        time.sleep(0.02)

    assert saw_waiting_shared_lock, (
        "the script did not acquire a shared flock on the regular file before reading it"
    )
    release.write_text("release")
    locker.wait(timeout=5)
    result = runner.wait(timeout=15)
    assert result == 0, f"archive_configs.py exited with status {result}"
finally:
    release.touch(exist_ok=True)
    if locker.poll() is None:
        try:
            locker.wait(timeout=2)
        except subprocess.TimeoutExpired:
            locker.kill()
    if runner is not None and runner.poll() is None:
        runner.kill()
    ready.unlink(missing_ok=True)
    release.unlink(missing_ok=True)

expected_archive_names = {f"{name_a}.tar.gz", f"{name_b}.tar.gz"}
actual_archive_names = {p.name for p in ARCHIVES.iterdir() if p.name.endswith(".tar.gz")}
assert actual_archive_names == expected_archive_names, (
    f"archives must be derived from the runtime log; expected {expected_archive_names}, "
    f"got {actual_archive_names}"
)

expected_skipped = sorted([
    str(target_a / "cycle_one.lnk"),
    str(target_a / "cycle_two.lnk"),
    str(target_b / "self_loop.lnk"),
])
assert SKIPPED.is_file(), "skipped_links.txt was not created"
actual_skipped = [line.strip() for line in SKIPPED.read_text().splitlines() if line.strip()]
assert actual_skipped == expected_skipped, (
    f"expected sorted skipped links {expected_skipped}, got {actual_skipped}"
)


def verify_archive(path, expected):
    assert path.is_file(), f"missing archive {path}"
    with tarfile.open(path, "r:gz") as tar:
        members = tar.getmembers()
        regular = {}
        for member in members:
            assert not member.name.startswith("/"), f"absolute archive member: {member.name}"
            normalized = posixpath.normpath(member.name)
            while normalized.startswith("./"):
                normalized = normalized[2:]
            assert normalized != ".." and not normalized.startswith("../"), (
                f"archive member escapes the target root: {member.name}"
            )
            if member.isfile():
                extracted = tar.extractfile(member)
                assert extracted is not None
                regular[normalized] = extracted.read()
            else:
                assert not member.issym() and not member.islnk(), (
                    f"symlink was stored instead of dereferenced: {member.name}"
                )
        assert set(regular) == set(expected), (
            f"wrong regular members in {path.name}: expected {set(expected)}, got {set(regular)}"
        )
        for name, data in expected.items():
            assert regular[name] == data, f"incorrect content for {name} in {path.name}"


verify_archive(ARCHIVES / f"{name_a}.tar.gz", {
    "000_locked.conf": final_locked_data.encode(),
    "nested/main.conf": main_data.encode(),
    "valid_alias.conf": main_data.encode(),
})
verify_archive(ARCHIVES / f"{name_b}.tar.gz", {
    "settings.conf": settings_data.encode(),
    "cross_alias.conf": main_data.encode(),
})
PY

ok=1
python3 -m pytest /tmp/test_original_state.py -x --tb=short || ok=0
if [ "$ok" -eq 1 ]; then
    python3 /tmp/test_dynamic_execution.py || ok=0
fi

if [ "$ok" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
