#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'SITE_EOF' > /tmp/sitecustomize.py
import hashlib
import json
import os
import tempfile

_trace = os.environ.get("ORG_TRACE")
_temps = set()


def _norm(path):
    try:
        return os.path.abspath(os.fspath(path))
    except (TypeError, ValueError):
        return None


def _log(event):
    if not _trace:
        return
    with open(_trace, "a", encoding="utf-8") as handle:
        handle.write(json.dumps(event, sort_keys=True) + "\n")


def _record_temp(path, kind):
    path = _norm(path)
    if path is not None:
        _temps.add(path)
        _log({"event": "temp", "kind": kind, "path": path})


if _trace:
    _original_named_temporary_file = tempfile.NamedTemporaryFile
    _original_mkstemp = tempfile.mkstemp
    _original_mktemp = tempfile.mktemp

    def _named_temporary_file(*args, **kwargs):
        result = _original_named_temporary_file(*args, **kwargs)
        _record_temp(result.name, "NamedTemporaryFile")
        return result

    def _mkstemp(*args, **kwargs):
        fd, path = _original_mkstemp(*args, **kwargs)
        _record_temp(path, "mkstemp")
        return fd, path

    def _mktemp(*args, **kwargs):
        path = _original_mktemp(*args, **kwargs)
        _record_temp(path, "mktemp")
        return path

    tempfile.NamedTemporaryFile = _named_temporary_file
    tempfile.mkstemp = _mkstemp
    tempfile.mktemp = _mktemp

    _original_replace = os.replace
    _original_rename = os.rename

    def _after_atomic(kind, src, dst):
        src_path = _norm(src)
        dst_path = _norm(dst)
        digest = None
        if src_path in _temps and dst_path == "/home/user/src_archive.tar.gz" and os.path.isfile(dst_path):
            with open(dst_path, "rb") as handle:
                digest = hashlib.sha256(handle.read()).hexdigest()
        _log({
            "event": "atomic",
            "kind": kind,
            "src": src_path,
            "dst": dst_path,
            "source_was_temp": src_path in _temps,
            "sha256": digest,
        })

    def _replace(src, dst, *args, **kwargs):
        result = _original_replace(src, dst, *args, **kwargs)
        _after_atomic("replace", src, dst)
        return result

    def _rename(src, dst, *args, **kwargs):
        result = _original_rename(src, dst, *args, **kwargs)
        _after_atomic("rename", src, dst)
        return result

    os.replace = _replace
    os.rename = _rename
SITE_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import uuid

import pytest

SCRIPT = Path("/home/user/organize.py")
SOURCE = Path("/home/user/projects_raw")
DEST = Path("/home/user/organized_src")
ARCHIVE = Path("/home/user/src_archive.tar.gz")
TRACE = Path("/tmp/organize_trace.jsonl")


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    assert SCRIPT.is_file(), f"Script {SCRIPT} does not exist."

    token = uuid.uuid4().hex
    nested = SOURCE / ("dynamic_" + token) / "deep" / "tree"
    nested.mkdir(parents=True)
    dynamic_name = "probe_" + token + ".py"
    dynamic_content = ("# dynamically supplied input\nVALUE = %r\n" % token).encode()
    (nested / dynamic_name).write_bytes(dynamic_content)
    (nested / ("ignore_" + token + ".txt")).write_text("not Python\n")

    expected = {}
    for root, _, files in os.walk(SOURCE):
        for filename in files:
            if filename.endswith(".py"):
                assert filename not in expected, "Source Python filenames must be unique"
                expected[filename] = (Path(root) / filename).read_bytes()

    if os.path.lexists(DEST):
        if DEST.is_symlink() or not DEST.is_dir():
            DEST.unlink()
        else:
            shutil.rmtree(DEST)
    if os.path.lexists(ARCHIVE):
        ARCHIVE.unlink()
    TRACE.write_text("")
    TRACE.chmod(0o666)

    env = os.environ.copy()
    env["PYTHONPATH"] = "/tmp"
    env["ORG_TRACE"] = str(TRACE)
    result = subprocess.run(
        ["python3", str(SCRIPT)],
        cwd="/home/user",
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"organize.py exited with {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return expected


def test_script_exists_and_uses_tempfile(execute_submission):
    assert SCRIPT.is_file(), f"Script {SCRIPT} does not exist."
    content = SCRIPT.read_text()
    assert "tempfile" in content, "The script does not seem to use the 'tempfile' module as required."


def test_organized_src_directory(execute_submission):
    expected = execute_submission
    assert DEST.is_dir(), f"Directory {DEST} does not exist."

    expected_outputs = {"src_" + name: data for name, data in expected.items()}
    actual_names = set(os.listdir(DEST))
    assert actual_names == set(expected_outputs), (
        f"organized_src contents differ from recursively discovered .py files: {actual_names}"
    )

    for filename, expected_content in expected_outputs.items():
        path = DEST / filename
        assert path.is_file() and not path.is_symlink(), f"{path} is not a regular file"
        assert path.read_bytes() == expected_content, f"Content of {filename} is incorrect."

    baseline = {
        "src_main.py": b"print('main')\n",
        "src_utils.py": b"print('utils')\n",
        "src_auth.py": b"print('auth')\n",
        "src_db.py": b"print('db')\n",
    }
    for filename, content in baseline.items():
        assert (DEST / filename).read_bytes() == content


def test_archive_exists_and_contents(execute_submission):
    expected_outputs = {"src_" + name: data for name, data in execute_submission.items()}
    assert ARCHIVE.is_file(), f"Archive {ARCHIVE} does not exist."

    archived = {}
    with tarfile.open(ARCHIVE, "r:gz") as tar:
        for member in tar.getmembers():
            if member.isdir():
                continue
            assert member.isfile(), f"Unexpected non-file archive member: {member.name}"
            basename = os.path.basename(member.name)
            assert basename not in archived, f"Duplicate archived filename: {basename}"
            extracted = tar.extractfile(member)
            assert extracted is not None
            archived[basename] = extracted.read()

    assert set(archived) == set(expected_outputs), "Archive does not contain exactly the organized files"
    for filename, expected_content in expected_outputs.items():
        assert archived[filename] == expected_content, f"Archived content of {filename} is incorrect"

    for expected in ["src_main.py", "src_utils.py", "src_auth.py", "src_db.py"]:
        assert expected in archived, f"Expected file {expected} not found in archive {ARCHIVE}."


def test_archive_was_atomically_installed_from_tempfile(execute_submission):
    events = []
    for line in TRACE.read_text().splitlines():
        if line.strip():
            events.append(json.loads(line))

    temp_paths = {e["path"] for e in events if e.get("event") == "temp"}
    assert temp_paths, "No temporary filename was created through Python's tempfile module"

    final_hash = hashlib.sha256(ARCHIVE.read_bytes()).hexdigest()
    matching = [
        e for e in events
        if e.get("event") == "atomic"
        and e.get("dst") == str(ARCHIVE)
        and e.get("src") in temp_paths
        and e.get("source_was_temp") is True
        and e.get("sha256") == final_hash
    ]
    assert matching, "The final archive was not atomically renamed/replaced from a tempfile-created path"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
