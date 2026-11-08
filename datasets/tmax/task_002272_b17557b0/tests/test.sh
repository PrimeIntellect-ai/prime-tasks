#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_storage_cleaner.py
import json
import os
import subprocess
import tarfile
import tempfile
import uuid
import zipfile
from pathlib import Path

import pytest

SCRIPT_PATH = "/home/user/storage_cleaner.py"
CLEAN_DIR = "/app/corpora/clean"
EVIL_DIR = "/app/corpora/evil"
ERROR_CODE = "ERR9X"


def run_cleaner(target, env=None, cwd=None):
    result = subprocess.run(
        ["python3", SCRIPT_PATH, str(target)],
        capture_output=True,
        text=True,
        timeout=30,
        env=env,
        cwd=cwd,
    )
    assert result.returncode == 0, (
        f"Script failed on {target}:\nSTDOUT: {result.stdout}\nSTDERR: {result.stderr}"
    )
    return result


@pytest.fixture(scope="session", autouse=True)
def run_on_original_corpora():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert not os.path.islink(SCRIPT_PATH), "storage_cleaner.py must be a regular script"

    run_cleaner(CLEAN_DIR)
    run_cleaner(EVIL_DIR)


def test_clean_corpus_unmodified():
    valid_zip = os.path.join(CLEAN_DIR, "valid_archive.zip")
    assert os.path.isfile(valid_zip), "Clean corpus: valid_archive.zip was incorrectly deleted."
    assert zipfile.is_zipfile(valid_zip), "Clean corpus: valid_archive.zip was corrupted."
    with zipfile.ZipFile(valid_zip) as archive:
        assert archive.testzip() is None, "Clean corpus: valid_archive.zip failed integrity checking."

    safe_link = os.path.join(CLEAN_DIR, "safe_link")
    assert os.path.islink(safe_link), "Clean corpus: safe_link was incorrectly deleted or modified."

    app_log = os.path.join(CLEAN_DIR, "app.log")
    assert os.path.isfile(app_log), "Clean corpus: app.log was incorrectly deleted."
    with open(app_log, "r") as f:
        content = f.read()
    assert "[REDACTED]" not in content, "Clean corpus: app.log was incorrectly redacted."


def test_evil_corpus_sanitized():
    corrupt_zip = os.path.join(EVIL_DIR, "corrupt_archive.zip")
    assert not os.path.lexists(corrupt_zip), "Evil corpus: corrupt_archive.zip was not deleted."

    infinite_link = os.path.join(EVIL_DIR, "loop_dir", "infinite")
    assert not os.path.lexists(infinite_link), "Evil corpus: infinite symlink was not deleted."

    error_log = os.path.join(EVIL_DIR, "error.log")
    assert os.path.isfile(error_log), "Evil corpus: error.log was deleted instead of redacted."
    with open(error_log, "r") as f:
        content = f.read()
    assert ERROR_CODE not in content, "Evil corpus: error.log still contains ERR9X."
    assert "[REDACTED]" in content, "Evil corpus: error.log lacks replacements."


def tree_snapshot(root):
    result = {}

    def visit(directory):
        for entry in os.scandir(directory):
            rel = os.path.relpath(entry.path, root)
            if entry.is_symlink():
                result[rel] = ("link", os.readlink(entry.path))
            elif entry.is_dir(follow_symlinks=False):
                result[rel] = ("dir",)
                visit(entry.path)
            elif entry.is_file(follow_symlinks=False):
                result[rel] = ("file", Path(entry.path).read_bytes())
            else:
                result[rel] = ("other",)

    visit(root)
    return result


def make_crc_bad_zip(path, marker):
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_STORED) as archive:
        archive.writestr("payload.txt", marker)
    data = bytearray(Path(path).read_bytes())
    needle = marker.encode()
    offset = data.find(needle)
    assert offset >= 0
    data[offset] ^= 1
    Path(path).write_bytes(data)
    assert zipfile.is_zipfile(path)


def make_valid_tar(path, name, content):
    source = path.parent / (name + ".source")
    source.write_text(content)
    with tarfile.open(path, "w:gz") as archive:
        archive.add(source, arcname=name)
    source.unlink()


def normalized_event_path(value, cwd):
    if not os.path.isabs(value):
        value = os.path.join(cwd, value)
    return os.path.normpath(value)


def test_general_recursive_behavior_archive_integrity_logging_and_atomic_writes(tmp_path):
    token = uuid.uuid4().hex
    root = tmp_path / ("case_" + token)
    deep = root / "level1" / "level2" / "level3"
    archives = deep / "archives"
    logs = deep / "logs"
    links = deep / "links"
    archives.mkdir(parents=True)
    logs.mkdir()
    links.mkdir()

    ordinary = root / "ordinary.bin"
    ordinary.write_bytes(os.urandom(257))
    clean_log = root / "normal.log"
    clean_log.write_text("ordinary cluster activity\n")

    valid_zip = archives / ("valid_" + token + ".zip")
    with zipfile.ZipFile(valid_zip, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("nested/data.txt", "valid zip " + token)

    bad_crc_zip = archives / ("bad_crc_" + token + ".zip")
    make_crc_bad_zip(bad_crc_zip, "unique zip payload " + token)
    fake_zip = archives / ("fake_" + token + ".zip")
    fake_zip.write_text("not a zip archive")

    valid_tar = archives / ("valid_" + token + ".tar.gz")
    make_valid_tar(valid_tar, "inside.txt", "valid tar " + token)
    corrupt_tar = archives / ("truncated_" + token + ".tar.gz")
    make_valid_tar(corrupt_tar, "broken.txt", "broken tar " + token)
    tar_bytes = corrupt_tar.read_bytes()
    corrupt_tar.write_bytes(tar_bytes[: max(12, len(tar_bytes) // 2)])
    fake_tar = archives / ("fake_" + token + ".tar.gz")
    fake_tar.write_bytes(b"not gzip or tar")

    first_log = logs / ("incident_a_" + token + ".log")
    second_log = root / ("incident_b_" + token + ".log")
    first_original = f"prefix {ERROR_CODE} middle {ERROR_CODE} suffix\n"
    second_original = f"{ERROR_CODE}\nunchanged text\n{ERROR_CODE}{ERROR_CODE}\n"
    first_log.write_text(first_original)
    second_log.write_text(second_original)

    safe_target = root / ("safe_target_" + token + ".txt")
    safe_target.write_text("safe target")
    safe_link = links / ("safe_link_" + token)
    safe_link.symlink_to(os.path.relpath(safe_target, links))

    self_name = "self_loop_" + token
    ancestor_name = "ancestor_loop_" + token
    absolute_name = "absolute_loop_" + token
    (links / self_name).symlink_to(".")
    (links / ancestor_name).symlink_to("../../..")
    (links / absolute_name).symlink_to(str(root.resolve()))

    valid_zip_before = valid_zip.read_bytes()
    valid_tar_before = valid_tar.read_bytes()
    ordinary_before = ordinary.read_bytes()
    clean_log_before = clean_log.read_bytes()

    hook_dir = tmp_path / ("hook_" + token)
    hook_dir.mkdir()
    trace_path = tmp_path / ("rename_trace_" + token + ".jsonl")
    (hook_dir / "sitecustomize.py").write_text(
        "import json, os\n"
        "_trace = os.environ.get('CLEANER_RENAME_TRACE')\n"
        "def _hook(event, args):\n"
        "    if event == 'os.rename' and _trace:\n"
        "        try:\n"
        "            src, dst = os.fsdecode(args[0]), os.fsdecode(args[1])\n"
        "            fd = os.open(_trace, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)\n"
        "            try:\n"
        "                os.write(fd, (json.dumps([src, dst]) + '\\\\n').encode())\n"
        "            finally:\n"
        "                os.close(fd)\n"
        "        except Exception:\n"
        "            pass\n"
        "import sys\n"
        "sys.addaudithook(_hook)\n"
    )

    env = os.environ.copy()
    env["CLEANER_RENAME_TRACE"] = str(trace_path)
    env["PYTHONPATH"] = str(hook_dir) + os.pathsep + env.get("PYTHONPATH", "")
    run_result = run_cleaner(root, env=env, cwd=root)

    assert valid_zip.read_bytes() == valid_zip_before
    with zipfile.ZipFile(valid_zip) as archive:
        assert archive.testzip() is None
    assert valid_tar.read_bytes() == valid_tar_before
    with tarfile.open(valid_tar, "r:gz") as archive:
        assert archive.getmembers()
    assert ordinary.read_bytes() == ordinary_before
    assert clean_log.read_bytes() == clean_log_before
    assert safe_link.is_symlink() and os.readlink(safe_link) == os.path.relpath(safe_target, links)

    for bad_archive in (bad_crc_zip, fake_zip, corrupt_tar, fake_tar):
        assert not os.path.lexists(bad_archive), f"Corrupt archive was retained: {bad_archive}"

    for bad_link in (links / self_name, links / ancestor_name, links / absolute_name):
        assert not os.path.lexists(bad_link), f"Ancestor-pointing symlink was retained: {bad_link}"

    assert first_log.read_text() == first_original.replace(ERROR_CODE, "[REDACTED]")
    assert second_log.read_text() == second_original.replace(ERROR_CODE, "[REDACTED]")

    logged_text = run_result.stdout + "\n" + run_result.stderr
    for path in root.rglob("*"):
        if path.is_file() and not path.is_symlink():
            try:
                logged_text += "\n" + path.read_text(errors="ignore")
            except OSError:
                pass
    for link_name in (self_name, ancestor_name, absolute_name):
        assert link_name in logged_text, f"Removal of {link_name} was not logged"

    assert trace_path.exists(), "No rename operations were observed during log sanitization"
    events = []
    for line in trace_path.read_text().splitlines():
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            pass

    destinations = {}
    for src, dst in events:
        destination = normalized_event_path(dst, str(root))
        destinations.setdefault(destination, []).append(normalized_event_path(src, str(root)))

    for changed_log in (first_log, second_log):
        destination = os.path.normpath(str(changed_log))
        assert destination in destinations, f"{changed_log} was not installed with an atomic rename"
        assert any(source != destination for source in destinations[destination]), (
            f"{changed_log} was not renamed from a separate temporary file"
        )


def test_random_clean_tree_is_functionally_unchanged(tmp_path):
    token = uuid.uuid4().hex
    root = tmp_path / ("clean_" + token)
    nested = root / "a" / "b" / "c"
    nested.mkdir(parents=True)
    (root / "plain.txt").write_text("plain " + token)
    (nested / "normal.log").write_text("no incident code here\n")
    with zipfile.ZipFile(nested / "good.zip", "w") as archive:
        archive.writestr("x.txt", token)
    make_valid_tar(nested / "good.tar.gz", "y.txt", token)
    (root / "safe-target.txt").write_text("target")
    (nested / "safe-link").symlink_to(os.path.relpath(root / "safe-target.txt", nested))

    before = tree_snapshot(root)
    run_cleaner(root)
    after = tree_snapshot(root)
    assert after == before, "A clean recursively nested tree was modified"
TEST_EOF

if python3 -m pytest /tmp/test_storage_cleaner.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
