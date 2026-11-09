#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import json
import os
import secrets
import subprocess
import sys
import time
import zipfile
from pathlib import Path


def test_script_exists():
    script_path = "/home/user/atomic_update.py"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."


def test_script_uses_required_modules():
    script_path = "/home/user/atomic_update.py"
    with open(script_path, "r") as f:
        content = f.read()

    assert "fcntl" in content, "Script does not import or use fcntl for file locking."
    assert "tempfile" in content, "Script does not use tempfile for atomic writes."
    assert "os.replace" in content or "replace" in content, "Script does not use os.replace for atomic replacement."


def test_lockfile_exists():
    lock_path = "/home/user/master_config.zip.lock"
    assert os.path.isfile(lock_path), f"Lockfile {lock_path} was not created."


def test_zip_archive_updated_correctly():
    zip_path = "/home/user/master_config.zip"
    assert os.path.isfile(zip_path), f"Archive {zip_path} does not exist."
    assert zipfile.is_zipfile(zip_path), f"Archive {zip_path} is not a valid zip file."

    with zipfile.ZipFile(zip_path, 'r') as z:
        files = z.namelist()

        assert "db.json" in files, "db.json missing from updated archive."
        assert "cache.json" in files, "cache.json missing from updated archive."
        assert "web.json" in files, "web.json missing from updated archive."

        with z.open("db.json") as f:
            db_content = f.read().decode('utf-8').strip()
            assert db_content == '{"db_host": "new.local", "port": 5432}', "db.json was not properly updated from incoming configs."

        with z.open("cache.json") as f:
            cache_content = f.read().decode('utf-8').strip()
            assert cache_content == '{"cache_size": 1024}', "cache.json was not properly added from incoming configs."

        with z.open("web.json") as f:
            web_content = f.read().decode('utf-8').strip()
            assert web_content == '{"workers": 4}', "web.json was incorrectly modified or removed."


def test_dynamic_merge_locking_tempfile_and_atomic_replace(tmp_path):
    token = secrets.token_hex(12)
    zip_path = tmp_path / f"archive_{token}.zip"
    incoming = tmp_path / f"incoming_{token}"
    incoming.mkdir()

    retained_name = f"retained_{token}.bin"
    replaced_name = f"replaced_{token}.bin"
    added_name = f"added_{token}.bin"
    retained_data = secrets.token_bytes(73)
    old_data = secrets.token_bytes(61)
    replacement_data = secrets.token_bytes(89)
    added_data = secrets.token_bytes(97)

    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        zf.writestr(retained_name, retained_data)
        zf.writestr(replaced_name, old_data)

    (incoming / replaced_name).write_bytes(replacement_data)
    (incoming / added_name).write_bytes(added_data)

    hook_dir = tmp_path / "hook"
    hook_dir.mkdir()
    event_log = tmp_path / "events.jsonl"
    (hook_dir / "sitecustomize.py").write_text(r'''
import fcntl
import json
import os
import tempfile

_log_path = os.environ.get("ATOMIC_TEST_EVENT_LOG")

def _emit(kind, **values):
    if not _log_path:
        return
    record = {"kind": kind}
    record.update(values)
    with open(_log_path, "a", encoding="utf-8") as stream:
        stream.write(json.dumps(record) + "\\n")

_real_flock = fcntl.flock
def _flock(fd, operation):
    if operation & fcntl.LOCK_UN:
        _emit("unlock", api="flock")
    elif operation & fcntl.LOCK_EX:
        _emit("lock_ex", api="flock")
    return _real_flock(fd, operation)
fcntl.flock = _flock

_real_lockf = fcntl.lockf
def _lockf(fd, operation, *args, **kwargs):
    if operation & fcntl.LOCK_UN:
        _emit("unlock", api="lockf")
    elif operation & fcntl.LOCK_EX:
        _emit("lock_ex", api="lockf")
    return _real_lockf(fd, operation, *args, **kwargs)
fcntl.lockf = _lockf

_real_mkstemp = tempfile.mkstemp
def _mkstemp(*args, **kwargs):
    result = _real_mkstemp(*args, **kwargs)
    _emit("tempfile", path=os.path.abspath(os.fspath(result[1])), temp_kind="file")
    return result
tempfile.mkstemp = _mkstemp

_real_named = tempfile.NamedTemporaryFile
def _named(*args, **kwargs):
    result = _real_named(*args, **kwargs)
    _emit("tempfile", path=os.path.abspath(os.fspath(result.name)), temp_kind="file")
    return result
tempfile.NamedTemporaryFile = _named

_real_temporary_file = tempfile.TemporaryFile
def _temporary_file(*args, **kwargs):
    result = _real_temporary_file(*args, **kwargs)
    name = getattr(result, "name", None)
    if isinstance(name, (str, bytes, os.PathLike)):
        _emit("tempfile", path=os.path.abspath(os.fspath(name)), temp_kind="file")
    else:
        _emit("tempfile", path="", temp_kind="anonymous")
    return result
tempfile.TemporaryFile = _temporary_file

_real_mkdtemp = tempfile.mkdtemp
def _mkdtemp(*args, **kwargs):
    result = _real_mkdtemp(*args, **kwargs)
    _emit("tempfile", path=os.path.abspath(os.fspath(result)), temp_kind="dir")
    return result
tempfile.mkdtemp = _mkdtemp

_real_tempdir = tempfile.TemporaryDirectory
def _tempdir(*args, **kwargs):
    result = _real_tempdir(*args, **kwargs)
    _emit("tempfile", path=os.path.abspath(os.fspath(result.name)), temp_kind="dir")
    return result
tempfile.TemporaryDirectory = _tempdir

_real_replace = os.replace
def _replace(src, dst, *args, **kwargs):
    result = _real_replace(src, dst, *args, **kwargs)
    _emit("replace", src=os.path.abspath(os.fspath(src)), dst=os.path.abspath(os.fspath(dst)))
    return result
os.replace = _replace
''', encoding="utf-8")

    lock_path = Path(str(zip_path) + ".lock")
    lock_file = open(lock_path, "a+b")
    fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    fcntl.lockf(lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    original_archive = zip_path.read_bytes()

    env = os.environ.copy()
    env["ATOMIC_TEST_EVENT_LOG"] = str(event_log)
    env["PYTHONPATH"] = str(hook_dir) + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
    proc = subprocess.Popen(
        [sys.executable, "/home/user/atomic_update.py", str(zip_path), str(incoming)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
    )

    try:
        time.sleep(1.0)
        assert proc.poll() is None, "Updater did not block while the archive lockfile was exclusively locked."
        assert zip_path.read_bytes() == original_archive, "Updater touched the archive before acquiring its lock."
    finally:
        fcntl.lockf(lock_file.fileno(), fcntl.LOCK_UN)
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
        lock_file.close()

    stdout, stderr = proc.communicate(timeout=15)
    assert proc.returncode == 0, f"Updater failed on dynamic input. stdout={stdout!r} stderr={stderr!r}"
    assert lock_path.is_file(), "Updater did not use the required <archive>.lock lockfile."
    assert zipfile.is_zipfile(zip_path), "Dynamically updated archive is not a valid ZIP file."

    with zipfile.ZipFile(zip_path, "r") as zf:
        assert set(zf.namelist()) == {retained_name, replaced_name, added_name}, "Archive merge produced missing or unexpected entries."
        assert zf.read(retained_name) == retained_data, "An existing non-overridden entry was not preserved."
        assert zf.read(replaced_name) == replacement_data, "Incoming content did not override the same-named archive entry."
        assert zf.read(added_name) == added_data, "A new incoming file was not added."

    assert event_log.is_file(), "No runtime evidence of required locking, tempfile, and replacement operations was produced."
    events = [json.loads(line) for line in event_log.read_text(encoding="utf-8").splitlines() if line.strip()]
    lock_indices = [i for i, event in enumerate(events) if event.get("kind") == "lock_ex"]
    unlock_indices = [i for i, event in enumerate(events) if event.get("kind") == "unlock"]
    replace_indices = [i for i, event in enumerate(events) if event.get("kind") == "replace" and event.get("dst") == os.path.abspath(zip_path)]
    temp_indices = [i for i, event in enumerate(events) if event.get("kind") == "tempfile"]

    assert lock_indices, "The updater did not call fcntl locking with LOCK_EX."
    assert temp_indices, "The updater did not create its output through the tempfile module."
    assert replace_indices, "The updater did not call os.replace() on the target archive."
    assert unlock_indices, "The updater did not explicitly release its fcntl lock."

    replace_index = replace_indices[-1]
    replace_event = events[replace_index]
    replace_source = os.path.abspath(replace_event["src"])
    matching_temp = False
    matching_temp_index = None
    for i in temp_indices:
        event = events[i]
        temp_path = event.get("path", "")
        if event.get("temp_kind") == "file" and temp_path == replace_source:
            matching_temp = True
            matching_temp_index = i
            break
        if event.get("temp_kind") == "dir" and temp_path:
            try:
                if os.path.commonpath([replace_source, temp_path]) == temp_path:
                    matching_temp = True
                    matching_temp_index = i
                    break
            except ValueError:
                pass

    assert replace_source != os.path.abspath(zip_path), "The target archive itself was used as the temporary output."
    assert matching_temp, "The file passed to os.replace() was not created through tempfile."
    assert lock_indices[0] < matching_temp_index < replace_index, "Locking, temporary creation, and replacement occurred in the wrong order."
    assert any(i > replace_index for i in unlock_indices), "The lock was released before atomic replacement completed."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
