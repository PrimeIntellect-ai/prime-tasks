#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import configparser
import io
import os
import secrets
import subprocess
import sys
import tarfile

SCRIPT = "/home/user/validate_archive.py"
STORAGE = "/home/user/storage"
ARCHIVE = os.path.join(STORAGE, "incoming.tar")
CONFIG = os.path.join(STORAGE, "config.ini")
OUTPUT = os.path.join(STORAGE, "unsafe_members.txt")


def run_script(env=None):
    result = subprocess.run(
        [sys.executable, SCRIPT],
        cwd="/home/user",
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"validate_archive.py failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def read_output():
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} is missing."
    with open(OUTPUT, "r") as f:
        return [line.strip() for line in f if line.strip()]


def test_script_exists_and_uses_locking():
    assert os.path.isfile(SCRIPT), f"Script file {SCRIPT} is missing."
    with open(SCRIPT, "r") as f:
        content = f.read()
    assert "fcntl" in content, "Script does not appear to import or use fcntl."
    assert "LOCK_SH" in content, "Script does not appear to use LOCK_SH for shared locking."


def test_unsafe_members_file_and_script_execution():
    if os.path.exists(OUTPUT):
        os.unlink(OUTPUT)
    run_script()
    expected = ["logs/escape_hatch", "logs/system_passwd"]
    lines = read_output()
    assert lines == expected, (
        f"Output file contents do not match expected. Got: {lines}, Expected: {expected}"
    )


def write_case(safe_dir, token):
    parser = configparser.ConfigParser()
    parser["Paths"] = {"SafeDirectory": safe_dir}
    with open(CONFIG, "w") as f:
        parser.write(f)

    unsafe = [
        f"absolute_{token}",
        f"hard/{token}_escape",
        f"nested/{token}_escape",
    ]

    with tarfile.open(ARCHIVE, "w") as tar:
        data = b"dynamic test data"
        regular = tarfile.TarInfo("nested/data.txt")
        regular.size = len(data)
        tar.addfile(regular, io.BytesIO(data))

        safe_sym = tarfile.TarInfo(f"nested/safe_{token}")
        safe_sym.type = tarfile.SYMTYPE
        safe_sym.linkname = "data.txt"
        tar.addfile(safe_sym)

        inside_absolute = tarfile.TarInfo(f"inside_absolute_{token}")
        inside_absolute.type = tarfile.SYMTYPE
        inside_absolute.linkname = os.path.join(safe_dir, "nested", "data.txt")
        tar.addfile(inside_absolute)

        bad_relative = tarfile.TarInfo(f"nested/{token}_escape")
        bad_relative.type = tarfile.SYMTYPE
        bad_relative.linkname = "../../../outside.txt"
        tar.addfile(bad_relative)

        bad_absolute = tarfile.TarInfo(f"absolute_{token}")
        bad_absolute.type = tarfile.SYMTYPE
        bad_absolute.linkname = "/etc/passwd"
        tar.addfile(bad_absolute)

        safe_hard = tarfile.TarInfo(f"hard/{token}_safe")
        safe_hard.type = tarfile.LNKTYPE
        safe_hard.linkname = "nested/data.txt"
        tar.addfile(safe_hard)

        bad_hard = tarfile.TarInfo(f"hard/{token}_escape")
        bad_hard.type = tarfile.LNKTYPE
        bad_hard.linkname = "../outside.txt"
        tar.addfile(bad_hard)

    return sorted(unsafe)


def make_audit_module(directory):
    code = r'''
import fcntl
import os
import tarfile

_target = os.path.realpath(os.environ["VALIDATOR_AUDIT_TARGET"])
_events = os.environ["VALIDATOR_AUDIT_EVENTS"]
_locked = False


def emit(value):
    with open(_events, "a") as event_file:
        event_file.write(value + "\n")


def fd_path(fd):
    try:
        return os.path.realpath(os.readlink("/proc/self/fd/%d" % fd))
    except Exception:
        return None


_original_flock = fcntl.flock

def audited_flock(fd, operation):
    global _locked
    result = _original_flock(fd, operation)
    if fd_path(fd) == _target:
        if operation & fcntl.LOCK_SH and not operation & fcntl.LOCK_EX:
            _locked = True
            emit("LOCK_SH")
        elif operation & fcntl.LOCK_UN:
            _locked = False
    return result

fcntl.flock = audited_flock

_original_class_open = tarfile.TarFile.open.__func__
_original_next = tarfile.TarFile.next


def is_target(name, fileobj):
    if fileobj is not None:
        try:
            if fd_path(fileobj.fileno()) == _target:
                return True
        except Exception:
            pass
        try:
            if os.path.realpath(os.fspath(fileobj.name)) == _target:
                return True
        except Exception:
            pass
    try:
        return name is not None and os.path.realpath(os.fspath(name)) == _target
    except Exception:
        return False


def audited_open(cls, name=None, mode="r", fileobj=None, bufsize=10240, **kwargs):
    target = is_target(name, fileobj)
    if target and "|" not in mode:
        raise RuntimeError("incoming.tar was not opened in tar streaming mode")
    result = _original_class_open(
        cls, name=name, mode=mode, fileobj=fileobj, bufsize=bufsize, **kwargs
    )
    if target:
        result._validator_audit_target = True
        emit("STREAM_MODE")
    return result


def audited_next(self):
    if getattr(self, "_validator_audit_target", False):
        if not _locked:
            raise RuntimeError("archive member iteration occurred without LOCK_SH")
        emit("ITERATE_LOCKED")
    return _original_next(self)


tarfile.TarFile.open = classmethod(audited_open)
tarfile.open = tarfile.TarFile.open
tarfile.TarFile.next = audited_next
'''
    with open(os.path.join(directory, "sitecustomize.py"), "w") as f:
        f.write(code)


def test_dynamic_archives_locking_streaming_and_link_validation(tmp_path):
    original_archive = open(ARCHIVE, "rb").read()
    original_config = open(CONFIG, "rb").read()
    audit_dir = tmp_path / "audit"
    audit_dir.mkdir()
    make_audit_module(str(audit_dir))

    try:
        for index in range(2):
            token = secrets.token_hex(8)
            safe_dir = f"/home/user/storage/extracted_{token}"
            expected = write_case(safe_dir, token)
            if os.path.exists(OUTPUT):
                os.unlink(OUTPUT)

            events_file = tmp_path / f"events_{index}.txt"
            env = os.environ.copy()
            env["PYTHONPATH"] = str(audit_dir)
            env["VALIDATOR_AUDIT_TARGET"] = ARCHIVE
            env["VALIDATOR_AUDIT_EVENTS"] = str(events_file)
            run_script(env)

            assert read_output() == expected, (
                f"Dynamic archive was classified incorrectly. "
                f"Got {read_output()}, expected {expected}"
            )
            assert events_file.is_file(), "No runtime locking/streaming audit events were recorded."
            events = events_file.read_text().splitlines()
            assert "LOCK_SH" in events, "The running script did not acquire LOCK_SH on incoming.tar."
            assert "STREAM_MODE" in events, "The running script did not open incoming.tar in streaming tar mode."
            assert "ITERATE_LOCKED" in events, "Archive members were not iterated while LOCK_SH was held."
    finally:
        with open(ARCHIVE, "wb") as f:
            f.write(original_archive)
        with open(CONFIG, "wb") as f:
            f.write(original_config)
        if os.path.exists(OUTPUT):
            os.unlink(OUTPUT)
        run_script()

    assert read_output() == ["logs/escape_hatch", "logs/system_passwd"]
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
