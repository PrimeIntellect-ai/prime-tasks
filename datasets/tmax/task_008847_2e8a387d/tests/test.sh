#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import hashlib
import json
import os
import secrets
import subprocess
import sys
import tempfile
import time
import zipfile

SCRIPT = "/home/user/organize.py"
CONFIG = "/home/user/config.json"


def test_organize_script_exists():
    assert os.path.isfile(SCRIPT), "/home/user/organize.py does not exist."


def test_safe_files_extracted():
    safe_doc = "/home/user/backup/safe_doc.txt"
    app_py = "/home/user/backup/src/app.py"

    assert os.path.isfile(safe_doc), f"{safe_doc} does not exist."
    with open(safe_doc, "r") as f:
        assert f.read() == "This is a safe file.", f"Content of {safe_doc} is incorrect."

    assert os.path.isfile(app_py), f"{app_py} does not exist."
    with open(app_py, "r") as f:
        assert f.read() == 'print("Hello World")', f"Content of {app_py} is incorrect."


def test_malicious_files_not_extracted():
    assert not os.path.exists("/home/user/backup/evil.sh"), "evil.sh was extracted into backup dir!"
    assert not os.path.exists("/home/user/backup/another_evil.txt"), "another_evil.txt was extracted into backup dir!"
    assert not os.path.exists("/evil.sh"), "evil.sh was extracted to the root directory!"


def test_skipped_log():
    log_path = "/home/user/skipped.log"
    assert os.path.isfile(log_path), f"{log_path} does not exist."
    with open(log_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert "../../../evil.sh" in lines, "../../../evil.sh missing from skipped.log"
    assert "folder/../../another_evil.txt" in lines, "folder/../../another_evil.txt missing from skipped.log"
    assert len(lines) == 2, f"skipped.log contains unexpected entries: {lines}"


def test_state_json():
    state_path = "/home/user/state.json"
    assert os.path.isfile(state_path), f"{state_path} does not exist."

    with open(state_path, "r") as f:
        try:
            state = json.load(f)
        except json.JSONDecodeError:
            assert False, "state.json is not valid JSON."

    expected_safe_doc_md5 = hashlib.md5(b"This is a safe file.").hexdigest()
    expected_app_py_md5 = hashlib.md5(b'print("Hello World")').hexdigest()

    assert state.get("safe_doc.txt") == expected_safe_doc_md5, "MD5 for safe_doc.txt is missing or incorrect in state.json."
    assert state.get("src/app.py") == expected_app_py_md5, "MD5 for src/app.py is missing or incorrect in state.json."


def test_script_contains_required_functions():
    with open(SCRIPT, "r") as f:
        content = f.read()

    assert "fcntl.flock" in content, "Script does not use fcntl.flock as required."
    assert "os.replace" in content, "Script does not use os.replace as required."
    assert "os.fsync" in content, "Script does not use os.fsync as required."


def md5(data):
    return hashlib.md5(data).hexdigest()


def test_dynamic_archive_processing_locking_and_atomic_update():
    token = secrets.token_hex(10)
    root = tempfile.mkdtemp(prefix="organize-verifier-")
    incoming = os.path.join(root, "incoming")
    backup = os.path.join(root, "backup")
    state_file = os.path.join(root, "state.json")
    os.makedirs(incoming)
    os.makedirs(backup)

    new_name = f"docs/{token}.txt"
    second_name = f"pkg/{token}/module.bin"
    changed_name = f"changed/{token}.txt"
    unchanged_name = f"unchanged/{token}.txt"
    new_data = secrets.token_bytes(113)
    second_data = secrets.token_bytes(79)
    old_changed = secrets.token_bytes(41)
    new_changed = secrets.token_bytes(67)
    unchanged_data = secrets.token_bytes(53)
    legacy_data = secrets.token_bytes(23)
    legacy_name = f"legacy/{token}.dat"

    for rel, data in ((changed_name, old_changed), (unchanged_name, unchanged_data)):
        path = os.path.join(backup, *rel.split("/"))
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(data)

    unchanged_path = os.path.join(backup, *unchanged_name.split("/"))
    fixed_time = 946684800000000000
    os.utime(unchanged_path, ns=(fixed_time, fixed_time))
    unchanged_stat = os.stat(unchanged_path)

    initial_state = {
        changed_name: md5(old_changed),
        unchanged_name: md5(unchanged_data),
        legacy_name: md5(legacy_data),
    }
    with open(state_file, "w") as f:
        json.dump(initial_state, f)

    absolute_bad = f"/tmp/{token}-absolute-evil.txt"
    traversal_bad = f"escape/{token}/../../../{token}-traversal-evil.txt"
    with zipfile.ZipFile(os.path.join(incoming, f"first-{token}.zip"), "w") as zf:
        zf.writestr(new_name, new_data)
        zf.writestr(changed_name, new_changed)
        zf.writestr(absolute_bad, b"evil absolute")
    with zipfile.ZipFile(os.path.join(incoming, f"second-{token}.zip"), "w") as zf:
        zf.writestr(second_name, second_data)
        zf.writestr(unchanged_name, unchanged_data)
        zf.writestr(traversal_bad, b"evil traversal")

    with open(CONFIG, "rb") as f:
        original_config = f.read()
    with open(CONFIG, "w") as f:
        json.dump({"incoming_dir": incoming, "backup_dir": backup, "state_file": state_file}, f)
    skipped = "/home/user/skipped.log"
    if os.path.exists(skipped):
        os.unlink(skipped)

    instrument = tempfile.mkdtemp(prefix="organize-instrument-")
    event_log = os.path.join(root, "events.jsonl")
    sitecustomize = r'''
import fcntl
import json
import os

_event_log = os.environ.get("ORGANIZE_EVENT_LOG")
_orig_flock = fcntl.flock
_orig_fsync = os.fsync
_orig_replace = os.replace

def _path_for_fd(fd):
    try:
        return os.readlink("/proc/self/fd/%d" % fd)
    except Exception:
        return None

def _emit(event):
    if _event_log:
        with open(_event_log, "a") as out:
            out.write(json.dumps(event) + "\\n")

def traced_flock(fd, operation):
    result = _orig_flock(fd, operation)
    _emit({"kind": "flock", "path": _path_for_fd(fd), "operation": operation})
    return result

def traced_fsync(fd):
    result = _orig_fsync(fd)
    _emit({"kind": "fsync", "path": _path_for_fd(fd)})
    return result

def traced_replace(src, dst, *args, **kwargs):
    _emit({"kind": "replace", "src": os.fspath(src), "dst": os.fspath(dst)})
    return _orig_replace(src, dst, *args, **kwargs)

fcntl.flock = traced_flock
os.fsync = traced_fsync
os.replace = traced_replace
'''
    with open(os.path.join(instrument, "sitecustomize.py"), "w") as f:
        f.write(sitecustomize)

    env = os.environ.copy()
    env["PYTHONPATH"] = instrument
    env["ORGANIZE_EVENT_LOG"] = event_log
    try:
        run = subprocess.run([sys.executable, SCRIPT], env=env, capture_output=True, text=True, timeout=15)
        assert run.returncode == 0, f"organize.py failed on a generated archive: {run.stdout}\n{run.stderr}"

        expected_files = {
            new_name: new_data,
            second_name: second_data,
            changed_name: new_changed,
            unchanged_name: unchanged_data,
        }
        for rel, expected in expected_files.items():
            path = os.path.join(backup, *rel.split("/"))
            assert os.path.isfile(path), f"Generated safe member was not backed up: {rel}"
            with open(path, "rb") as f:
                assert f.read() == expected, f"Incorrect content for generated member: {rel}"

        after_unchanged = os.stat(unchanged_path)
        assert after_unchanged.st_ino == unchanged_stat.st_ino, "An unchanged file was unnecessarily replaced"
        assert after_unchanged.st_mtime_ns == unchanged_stat.st_mtime_ns, "An unchanged file was unnecessarily copied"

        assert not os.path.exists(absolute_bad), "An absolute ZIP member was extracted"
        assert not os.path.exists(os.path.join(backup, f"{token}-traversal-evil.txt")), "A traversal member entered the backup"
        with open(skipped) as f:
            skipped_lines = [line.rstrip("\n") for line in f if line.rstrip("\n")]
        assert sorted(skipped_lines) == sorted([absolute_bad, traversal_bad]), f"Incorrect generated skipped.log: {skipped_lines}"

        with open(state_file) as f:
            final_state = json.load(f)
        expected_state = dict(initial_state)
        expected_state.update({name: md5(data) for name, data in expected_files.items()})
        assert final_state == expected_state, f"Incorrect incremental state: {final_state}"

        with open(event_log) as f:
            events = [json.loads(line) for line in f if line.strip()]
        lock_events = [e for e in events if e.get("kind") == "flock"]
        assert any(os.path.abspath(e.get("path", "")) == "/home/user/backup.lock" and e.get("operation") == (fcntl.LOCK_EX | fcntl.LOCK_NB) for e in lock_events), "The executed script did not acquire backup.lock with LOCK_EX | LOCK_NB"

        replace_indices = [i for i, e in enumerate(events) if e.get("kind") == "replace" and os.path.abspath(e.get("dst", "")) == os.path.abspath(state_file)]
        assert replace_indices, "The executed script did not update the configured state file using os.replace"
        replace_index = replace_indices[-1]
        replace_event = events[replace_index]
        replace_src = os.path.abspath(replace_event["src"])
        assert os.path.dirname(replace_src) == os.path.dirname(os.path.abspath(state_file)), "State temporary file was not in the state file's directory"
        assert any(e.get("kind") == "fsync" and e.get("path") and os.path.abspath(e["path"]) == replace_src for e in events[:replace_index]), "The state temporary file was not fsynced before replacement"

        before_state = open(state_file, "rb").read()
        before_log = open(skipped, "rb").read()
        lock_handle = open("/home/user/backup.lock", "a+")
        fcntl.flock(lock_handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        started = time.monotonic()
        try:
            blocked = subprocess.run([sys.executable, SCRIPT], env=env, capture_output=True, text=True, timeout=4)
        finally:
            fcntl.flock(lock_handle.fileno(), fcntl.LOCK_UN)
            lock_handle.close()
        elapsed = time.monotonic() - started
        assert blocked.returncode == 1, f"Script returned {blocked.returncode}, not 1, when backup.lock was held"
        assert elapsed < 4, "Script did not exit immediately when backup.lock was held"
        assert open(state_file, "rb").read() == before_state, "Script changed state despite failing to acquire the lock"
        assert open(skipped, "rb").read() == before_log, "Script processed archives despite failing to acquire the lock"
    finally:
        with open(CONFIG, "wb") as f:
            f.write(original_config)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
