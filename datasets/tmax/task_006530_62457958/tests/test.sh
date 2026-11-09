#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import errno
import fcntl
import os
import subprocess
import sys
import tarfile
import time
import zipfile

HOME = "/home/user"
TARBALL = os.path.join(HOME, "legacy_configs.tar.gz")
CONVERTED = os.path.join(HOME, "converted_configs")
LATEST = os.path.join(HOME, "latest_configs")
ARCHIVE = os.path.join(HOME, "master_configs.zip")
LOCKFILE = os.path.join(HOME, "master.lock")
SCRIPT = os.path.join(HOME, "update_configs.py")
BASELINE = {"existing.conf": b"existing=true\n"}


def expected_configs():
    expected = {}
    with tarfile.open(TARBALL, "r:gz") as tf:
        for member in tf.getmembers():
            if member.isfile() and member.name.endswith(".conf"):
                source = tf.extractfile(member)
                assert source is not None
                name = os.path.basename(member.name)
                expected[name] = source.read().decode("iso-8859-1").encode("utf-8")
    assert expected, "No .conf files found in the legacy tarball."
    return expected


def reset_archive():
    with zipfile.ZipFile(ARCHIVE, "w") as zf:
        for name, data in BASELINE.items():
            zf.writestr(name, data)


def assert_archive(expected):
    assert os.path.isfile(ARCHIVE), f"Master zip {ARCHIVE} not found."
    with zipfile.ZipFile(ARCHIVE, "r") as zf:
        names = zf.namelist()
        assert "existing.conf" in names, "existing.conf is missing from master_configs.zip. The zip was likely overwritten instead of appended."
        assert "db.conf" in names, "db.conf not found in master_configs.zip."
        assert "web.conf" in names, "web.conf not found in master_configs.zip."
        assert zf.read("existing.conf") == BASELINE["existing.conf"], "existing.conf was altered."
        for name, data in expected.items():
            assert name in names, f"{name} not found in master_configs.zip."
            assert zf.read(name) == data, f"Archived content for {name} is incorrect."


def test_converted_configs():
    expected = expected_configs()
    assert os.path.isdir(CONVERTED), f"Directory {CONVERTED} not found."

    db_conf = os.path.join(CONVERTED, "db.conf")
    web_conf = os.path.join(CONVERTED, "web.conf")
    assert os.path.isfile(db_conf), "db.conf not found in converted_configs."
    assert os.path.isfile(web_conf), "web.conf not found in converted_configs."

    for name, data in expected.items():
        path = os.path.join(CONVERTED, name)
        assert os.path.isfile(path), f"{name} not found in converted_configs."
        raw = open(path, "rb").read()
        assert raw == data, f"{name} was not correctly converted from ISO-8859-1 to UTF-8."
        raw.decode("utf-8")

    with open(db_conf, "r", encoding="utf-8") as f:
        assert "Café database" in f.read(), "db.conf content is incorrect or corrupted during conversion."
    with open(web_conf, "r", encoding="utf-8") as f:
        assert "Bienvenue à la page" in f.read(), "web.conf content is incorrect or corrupted during conversion."


def test_python_script_and_locked_archive_workflow():
    expected = expected_configs()
    assert os.path.isfile(SCRIPT), "update_configs.py script not found."
    with open(SCRIPT, "r", encoding="utf-8") as f:
        content = f.read()
        assert "fcntl.flock" in content, "Python script does not seem to use fcntl.flock."

    runner = r'''
import errno
import fcntl
import os
import runpy
import sys
import zipfile

script, archive, lockfile = sys.argv[1:]
real_flock = fcntl.flock
real_zipfile = zipfile.ZipFile
state = {"locked": False, "lock_obj": None, "archive_open": 0,
         "saw_ex": False, "saw_zip": False, "saw_release": False}

def fd_number(obj):
    return obj if isinstance(obj, int) else obj.fileno()

def is_master_lock(obj):
    try:
        return os.path.realpath(os.readlink("/proc/self/fd/%d" % fd_number(obj))) == os.path.realpath(lockfile)
    except (OSError, ValueError):
        return False

def probe_locked():
    fd = os.open(lockfile, os.O_RDWR | os.O_CREAT, 0o666)
    acquired = False
    try:
        try:
            real_flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            acquired = True
        except BlockingIOError:
            pass
    finally:
        if acquired:
            real_flock(fd, fcntl.LOCK_UN)
        os.close(fd)
    assert not acquired, "master.lock is not actually held exclusively"

def tracking_flock(obj, operation):
    relevant = is_master_lock(obj)
    if relevant and (operation & fcntl.LOCK_UN):
        assert state["archive_open"] == 0, "master.lock was released before the ZIP was closed"
    result = real_flock(obj, operation)
    if relevant and (operation & fcntl.LOCK_EX):
        state["locked"] = True
        state["lock_obj"] = obj
        state["saw_ex"] = True
    if relevant and (operation & fcntl.LOCK_UN):
        state["locked"] = False
        state["saw_release"] = True
    return result

class TrackingZipFile(real_zipfile):
    def __init__(self, file, *args, **kwargs):
        self._tracked_archive = False
        path = os.fspath(file) if isinstance(file, (str, bytes, os.PathLike)) else None
        if path is not None and os.path.realpath(path) == os.path.realpath(archive):
            assert state["locked"], "master_configs.zip was opened before acquiring master.lock"
            probe_locked()
            state["archive_open"] += 1
            state["saw_zip"] = True
            self._tracked_archive = True
        try:
            super().__init__(file, *args, **kwargs)
        except BaseException:
            if self._tracked_archive:
                state["archive_open"] -= 1
                self._tracked_archive = False
            raise

    def close(self):
        tracked = self._tracked_archive and getattr(self, "fp", None) is not None
        if tracked:
            assert state["locked"], "master.lock was released while the ZIP was still open"
            probe_locked()
        try:
            return super().close()
        finally:
            if tracked:
                state["archive_open"] -= 1
                self._tracked_archive = False

fcntl.flock = tracking_flock
zipfile.ZipFile = TrackingZipFile
runpy.run_path(script, run_name="__main__")
assert state["saw_ex"], "script never acquired an exclusive flock on master.lock"
assert state["saw_zip"], "script never opened master_configs.zip"
assert state["archive_open"] == 0, "script did not close master_configs.zip"
if state["locked"]:
    obj = state["lock_obj"]
    if isinstance(obj, int):
        try:
            os.fstat(obj)
            closed = False
        except OSError as exc:
            closed = exc.errno == errno.EBADF
    else:
        closed = obj.closed
    assert closed, "script did not release or close the master.lock file after closing the ZIP"
'''
    runner_path = "/tmp/run_instrumented.py"
    with open(runner_path, "w", encoding="utf-8") as f:
        f.write(runner)

    reset_archive()
    result = subprocess.run(
        [sys.executable, runner_path, SCRIPT, ARCHIVE, LOCKFILE],
        text=True, capture_output=True, timeout=15
    )
    assert result.returncode == 0, "Instrumented execution failed:\n" + result.stdout + result.stderr
    assert_archive(expected)

    # Also exercise locking against a genuinely competing process execution.
    reset_archive()
    before = open(ARCHIVE, "rb").read()
    with open(LOCKFILE, "a+b") as held_lock:
        fcntl.flock(held_lock, fcntl.LOCK_EX)
        proc = subprocess.Popen(
            [sys.executable, SCRIPT], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        time.sleep(0.5)
        assert proc.poll() is None, "Script completed while another process held master.lock."
        assert open(ARCHIVE, "rb").read() == before, "Archive changed while master.lock was held by another process."
        fcntl.flock(held_lock, fcntl.LOCK_UN)
    stdout, stderr = proc.communicate(timeout=15)
    assert proc.returncode == 0, f"Script failed after lock release:\n{stdout}{stderr}"
    assert_archive(expected)


def test_symlinks():
    expected = expected_configs()
    assert os.path.isdir(LATEST), f"Directory {LATEST} not found."
    for filename in expected:
        link_path = os.path.join(LATEST, filename)
        assert os.path.islink(link_path), f"{link_path} is not a symlink."
        expected_target = os.path.join(CONVERTED, filename)
        assert os.path.realpath(link_path) == os.path.realpath(expected_target), (
            f"Symlink for {filename} does not point to {expected_target}."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
