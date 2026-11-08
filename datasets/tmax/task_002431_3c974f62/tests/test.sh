#!/bin/bash
set -e
mkdir -p /logs/verifier

cat > /tmp/backup_instrumentation.py <<'PY'
import json
import os
import tarfile

EVENTS = os.environ.get("BACKUP_EVENTS", "/tmp/backup_events.jsonl")
_recording = False

def record(kind, **fields):
    global _recording
    if _recording:
        return
    _recording = True
    try:
        with open(EVENTS, "a", encoding="utf-8") as f:
            f.write(json.dumps({"kind": kind, **fields}, default=str) + "\n")
    finally:
        _recording = False

def audit(event, args):
    if event == "open" and not _recording:
        path = args[0] if len(args) > 0 else None
        mode = args[1] if len(args) > 1 else None
        flags = args[2] if len(args) > 2 else None
        record("open", path=os.fspath(path) if path is not None else None,
               mode=mode, flags=flags)

import sys
sys.addaudithook(audit)

_original_rename = os.rename
_original_replace = os.replace

def tracked_rename(src, dst, *args, **kwargs):
    result = _original_rename(src, dst, *args, **kwargs)
    record("rename", src=os.fspath(src), dst=os.fspath(dst), operation="os.rename")
    return result

def tracked_replace(src, dst, *args, **kwargs):
    result = _original_replace(src, dst, *args, **kwargs)
    record("rename", src=os.fspath(src), dst=os.fspath(dst), operation="os.replace")
    return result

os.rename = tracked_rename
os.replace = tracked_replace

_original_tar_open = tarfile.open

def tracked_tar_open(name=None, mode="r", fileobj=None, **kwargs):
    record("tar-open", path=os.fspath(name) if name is not None else None, mode=mode)
    return _original_tar_open(name=name, mode=mode, fileobj=fileobj, **kwargs)

tarfile.open = tracked_tar_open

for method_name in ("getmembers", "getnames", "next", "extractfile"):
    original = getattr(tarfile.TarFile, method_name)
    def make_wrapper(method, operation):
        def wrapper(self, *args, **kwargs):
            name = getattr(self, "name", None)
            record("tar-read", path=os.fspath(name) if name is not None else None,
                   operation=operation)
            return method(self, *args, **kwargs)
        return wrapper
    setattr(tarfile.TarFile, method_name, make_wrapper(original, method_name))
PY

cat > /tmp/test_final_state.py <<'PY'
import json
import os
import re
import secrets
import stat
import subprocess
import sys
import tarfile

EXPECTED_FILES = [
    "/home/user/data_to_backup/a.txt",
    "/home/user/data_to_backup/b.bin",
    "/home/user/data_to_backup/dir1/c.txt",
    "/home/user/data_to_backup/dir2/d.txt",
]
ROOT = "/home/user/data_to_backup"
SCRIPT = "/home/user/safe_backup.py"
TAR_PATH = "/home/user/backup.tar.gz"
LOG_PATH = "/home/user/backup_log.txt"
EVENTS = "/tmp/backup_events.jsonl"


def normalized_member_name(name):
    return "/" + name.lstrip("/")


def collect_real_files(root):
    pending = [root]
    seen = set()
    files = []
    while pending:
        candidate = pending.pop()
        real = os.path.realpath(candidate)
        if real in seen:
            continue
        seen.add(real)
        try:
            info = os.stat(real)
        except (FileNotFoundError, OSError):
            continue
        if stat.S_ISDIR(info.st_mode):
            for entry in sorted(os.listdir(real), reverse=True):
                pending.append(os.path.join(real, entry))
        elif stat.S_ISREG(info.st_mode):
            files.append(real)
    return sorted(files)


def assert_archive_matches_source(expected):
    assert os.path.isfile(TAR_PATH), f"Tarball {TAR_PATH} is missing."
    assert tarfile.is_tarfile(TAR_PATH), f"File {TAR_PATH} is not a valid tar archive."

    with tarfile.open(TAR_PATH, "r:gz") as archive:
        members = archive.getmembers()
        actual_names = [normalized_member_name(member.name) for member in members]
        assert sorted(actual_names) == expected, (
            f"Tarball members differ from traversed real files. Expected {expected}, "
            f"got {sorted(actual_names)}"
        )
        assert len(actual_names) == len(set(actual_names)), "Tarball contains duplicate members."

        by_name = dict(zip(actual_names, members))
        for path in expected:
            member = by_name[path]
            assert member.isfile(), f"Archive member {path} is not a regular file."
            source_stat = os.stat(path)
            assert member.size == source_stat.st_size, f"Wrong archived size for {path}."
            assert stat.S_IMODE(member.mode) == stat.S_IMODE(source_stat.st_mode), (
                f"Wrong archived permission metadata for {path}."
            )
            assert member.uid == source_stat.st_uid and member.gid == source_stat.st_gid, (
                f"Wrong archived ownership metadata for {path}."
            )
            assert int(member.mtime) == int(source_stat.st_mtime), (
                f"Wrong archived modification time for {path}."
            )
            extracted = archive.extractfile(member)
            assert extracted is not None
            with extracted, open(path, "rb") as source:
                assert extracted.read() == source.read(), f"Wrong archived contents for {path}."


def test_complete_backup_behavior():
    # Preserve the original final-state assertions.
    assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} is missing."
    with open(LOG_PATH, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    assert lines == EXPECTED_FILES, (
        f"Contents of {LOG_PATH} do not match the expected sorted list of real absolute paths.\n"
        f"Expected: {EXPECTED_FILES}\nGot: {lines}"
    )

    assert os.path.isfile(TAR_PATH), f"Tarball {TAR_PATH} is missing."
    assert tarfile.is_tarfile(TAR_PATH), f"File {TAR_PATH} is not a valid tar archive."
    with tarfile.open(TAR_PATH, "r:gz") as archive:
        members = archive.getnames()
    expected_names_stripped = [p.lstrip("/") for p in EXPECTED_FILES]
    sorted_members = sorted(members)
    assert sorted_members == EXPECTED_FILES or sorted_members == expected_names_stripped, (
        f"Tarball {TAR_PATH} does not contain the correct files. Got: {sorted_members}"
    )

    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} is missing."
    with open(SCRIPT, "r") as f:
        content = f.read()
    pattern = r"(os\.rename|os\.replace|shutil\.move|Path\.rename|rename\()"
    assert re.search(pattern, content), (
        f"Script {SCRIPT} does not appear to use an atomic rename operation."
    )

    # Add unpredictable content and additional aliases/loops, then execute the artifact.
    token = secrets.token_hex(8)
    nested = os.path.join(ROOT, "dynamic_" + token, "nested")
    os.makedirs(nested)
    dynamic_file = os.path.join(nested, "payload_" + token + ".bin")
    dynamic_data = secrets.token_bytes(4096) + token.encode()
    with open(dynamic_file, "wb") as f:
        f.write(dynamic_data)
    os.symlink(dynamic_file, os.path.join(ROOT, "dynamic_file_link_" + token))
    os.symlink(ROOT, os.path.join(nested, "loop_to_root"))
    os.symlink(os.path.dirname(nested), os.path.join(ROOT, "dynamic_dir_link_" + token))

    expected = collect_real_files(ROOT)
    for path in (TAR_PATH, LOG_PATH, EVENTS):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    env = os.environ.copy()
    env["PYTHONPATH"] = "/tmp" + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
    env["BACKUP_EVENTS"] = EVENTS
    sitecustomize = "/tmp/sitecustomize.py"
    with open("/tmp/backup_instrumentation.py", "rb") as src, open(sitecustomize, "wb") as dst:
        dst.write(src.read())

    result = subprocess.run(
        [sys.executable, SCRIPT], env=env, cwd="/home/user",
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert result.returncode == 0, (
        f"Executing {SCRIPT} failed with code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    with open(LOG_PATH, "r") as f:
        new_lines = [line.strip() for line in f if line.strip()]
    assert new_lines == expected, f"Log was not the sorted set of traversed real files: {new_lines}"
    assert_archive_matches_source(expected)

    with open(EVENTS, "r", encoding="utf-8") as f:
        events = [json.loads(line) for line in f if line.strip()]

    final_abs = os.path.abspath(TAR_PATH)
    rename_events = []
    for index, event in enumerate(events):
        if event.get("kind") != "rename":
            continue
        src = os.path.abspath(event["src"])
        dst = os.path.abspath(event["dst"])
        if dst == final_abs:
            rename_events.append((index, src))
    assert rename_events, "No successful runtime atomic rename to backup.tar.gz was observed."
    rename_index, temporary = rename_events[-1]
    assert temporary != final_abs, "The final archive was not renamed from a temporary path."
    assert os.path.dirname(temporary) == os.path.dirname(final_abs), (
        "Temporary archive was not in the final archive's directory, so rename atomicity is not assured."
    )
    assert not os.path.exists(temporary), "Temporary archive remains after successful rename."

    write_before_rename = any(
        i < rename_index and event.get("kind") == "tar-open" and
        str(event.get("mode", "")).startswith(("w", "x", "a"))
        for i, event in enumerate(events)
    )
    assert write_before_rename, "No tar archive write was observed before the atomic rename."

    read_open_after = any(
        i > rename_index and event.get("kind") == "tar-open" and
        os.path.abspath(event.get("path")) == final_abs and
        str(event.get("mode", "r")).startswith("r")
        for i, event in enumerate(events) if event.get("path")
    )
    content_read_after = any(
        i > rename_index and event.get("kind") == "tar-read" and
        event.get("path") and os.path.abspath(event["path"]) == final_abs
        for i, event in enumerate(events)
    )
    assert read_open_after and content_read_after, (
        "The script did not programmatically reopen and read the finalized tarball to verify it."
    )
PY

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
