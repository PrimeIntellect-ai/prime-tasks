#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "yaml:pyyaml"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import subprocess
import tarfile
import tempfile
import uuid
import zipfile

import yaml

SCRIPT = "/home/user/organize.py"
PROCESSING = "/home/user/processing"
ARCHIVE = "/home/user/legacy_assets.tar.gz"
CLEAN_ZIP = "/home/user/clean_assets.zip"

EXPECTED = {
    "asset_config1.yaml": {"name": "ServiceA", "port": 8080, "processed": True},
    "asset_settings.yaml": {"name": "ServiceB", "enabled": False, "processed": True},
    "asset_root_level.yaml": {"app": "LegacyApp", "version": "1.0.0", "processed": True},
}


def load_yaml_bytes(data, name):
    value = yaml.safe_load(data.decode("utf-8"))
    assert isinstance(value, dict), f"{name} does not contain a YAML mapping."
    return value


def test_organize_py_exists_and_contains_flock():
    assert os.path.exists(SCRIPT), f"The script {SCRIPT} does not exist."
    assert os.path.isfile(SCRIPT), f"{SCRIPT} is not a file."
    with open(SCRIPT, "r", encoding="utf-8") as f:
        content = f.read()
    assert "fcntl.flock" in content, f"The script {SCRIPT} does not contain 'fcntl.flock'."
    assert "fcntl.LOCK_EX" in content, f"The script {SCRIPT} does not contain 'fcntl.LOCK_EX'."


def test_clean_assets_zip():
    assert os.path.exists(CLEAN_ZIP), f"The archive {CLEAN_ZIP} does not exist."
    assert os.path.isfile(CLEAN_ZIP), f"{CLEAN_ZIP} is not a file."
    assert zipfile.is_zipfile(CLEAN_ZIP), f"{CLEAN_ZIP} is not a valid ZIP file."

    expected_files = set(EXPECTED)
    with zipfile.ZipFile(CLEAN_ZIP, "r") as zf:
        namelist = zf.namelist()
        for name in namelist:
            assert "/" not in name and "\\" not in name, f"File {name} in the ZIP archive is not at the root level."
        assert len(namelist) == len(set(namelist)), "The ZIP contains duplicate entries."
        actual_files = set(namelist)
        assert actual_files == expected_files, f"ZIP contents mismatch. Expected {expected_files}, got {actual_files}."

        config1_content = zf.read("asset_config1.yaml").decode("utf-8")
        assert "processed: true" in config1_content or "processed: True" in config1_content, "asset_config1.yaml does not contain 'processed: true'."
        assert "ServiceA" in config1_content, "asset_config1.yaml is missing original data."

        for name, expected in EXPECTED.items():
            actual = load_yaml_bytes(zf.read(name), name)
            assert actual == expected, f"Incorrect YAML data in {name}: expected {expected}, got {actual}."


def test_processing_directory_state():
    assert os.path.exists(PROCESSING), f"The directory {PROCESSING} does not exist."
    assert os.path.isdir(PROCESSING), f"{PROCESSING} is not a directory."

    json_files = []
    yaml_files = []
    for root, dirs, files in os.walk(PROCESSING):
        for filename in files:
            path = os.path.join(root, filename)
            if filename.endswith(".json"):
                json_files.append(path)
            elif filename.endswith(".yaml"):
                yaml_files.append(path)

    assert len(json_files) == 0, f"Found leftover .json files in {PROCESSING}: {json_files}"
    expected_yaml_names = set(EXPECTED)
    actual_yaml_names = {os.path.basename(p) for p in yaml_files}
    assert expected_yaml_names.issubset(actual_yaml_names), f"Missing expected .yaml files in {PROCESSING}. Expected {expected_yaml_names}, got {actual_yaml_names}."
    assert len(yaml_files) == len(EXPECTED), f"Unexpected YAML files in {PROCESSING}: {yaml_files}"

    by_name = {os.path.basename(path): path for path in yaml_files}
    for name, expected in EXPECTED.items():
        with open(by_name[name], "rb") as f:
            actual = load_yaml_bytes(f.read(), by_name[name])
        assert actual == expected, f"Incorrect processed file {by_name[name]}: expected {expected}, got {actual}."


def test_script_actually_processes_dynamic_inputs_with_exclusive_locks():
    token = uuid.uuid4().hex
    dynamic = {
        f"alpha_{token}.json": {"marker": token, "count": 17, "active": False},
        f"nested/beta_{token}.json": {"marker": token[::-1], "items": [1, 2, 3]},
        f"nested/deeper/gamma_{token}.json": {"title": f"dynamic-{token}", "value": 4.25},
    }

    work = tempfile.mkdtemp(prefix="organize_verify_")
    backup_processing = os.path.join(work, "processing_backup")
    backup_archive = os.path.join(work, "archive_backup.tar.gz")
    backup_zip = os.path.join(work, "zip_backup.zip")
    source = os.path.join(work, "source")
    hooks = os.path.join(work, "hooks")
    lock_log = os.path.join(work, "events.jsonl")
    os.makedirs(source)
    os.makedirs(hooks)

    for relpath, value in dynamic.items():
        path = os.path.join(source, relpath)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(value, f)

    sitecustomize = r'''
import builtins
import fcntl
import io
import json
import os

_LOG = os.environ["ORGANIZE_LOCK_LOG"]
_real_flock = fcntl.flock
_real_builtin_open = builtins.open
_real_io_open = io.open


def _target(fd):
    try:
        return os.path.realpath(os.readlink("/proc/self/fd/%d" % fd))
    except Exception:
        return ""


def _relevant(path):
    return path.endswith(".json") and (path == "/home/user/processing" or path.startswith("/home/user/processing/"))


def _log(kind, path, op=None):
    record = {"kind": kind, "path": path}
    if op is not None:
        record["op"] = int(op)
    fd = os.open(_LOG, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o666)
    try:
        os.write(fd, (json.dumps(record) + "\n").encode("utf-8"))
    finally:
        os.close(fd)


def checked_flock(fd, op):
    result = _real_flock(fd, op)
    path = _target(fd)
    if _relevant(path):
        _log("LOCK", path, op)
    return result


class ReadWatcher:
    def __init__(self, wrapped, path):
        self._wrapped = wrapped
        self._path = path
    def _read_event(self):
        _log("READ", self._path)
    def read(self, *a, **k):
        self._read_event()
        return self._wrapped.read(*a, **k)
    def readline(self, *a, **k):
        self._read_event()
        return self._wrapped.readline(*a, **k)
    def readlines(self, *a, **k):
        self._read_event()
        return self._wrapped.readlines(*a, **k)
    def __iter__(self):
        return self
    def __next__(self):
        self._read_event()
        return next(self._wrapped)
    def __enter__(self):
        self._wrapped.__enter__()
        return self
    def __exit__(self, *a):
        return self._wrapped.__exit__(*a)
    def __getattr__(self, name):
        return getattr(self._wrapped, name)


def _wrap_open(real_open, file, *a, **k):
    result = real_open(file, *a, **k)
    try:
        path = os.path.realpath(os.fspath(file))
        mode = a[0] if a else k.get("mode", "r")
        if _relevant(path) and "r" in mode:
            return ReadWatcher(result, path)
    except Exception:
        pass
    return result


def builtin_open(file, *a, **k):
    return _wrap_open(_real_builtin_open, file, *a, **k)


def io_open(file, *a, **k):
    return _wrap_open(_real_io_open, file, *a, **k)

fcntl.flock = checked_flock
builtins.open = builtin_open
io.open = io_open
'''
    with open(os.path.join(hooks, "sitecustomize.py"), "w", encoding="utf-8") as f:
        f.write(sitecustomize)

    processing_saved = archive_saved = zip_saved = False
    try:
        if os.path.exists(PROCESSING):
            os.rename(PROCESSING, backup_processing)
            processing_saved = True
        os.makedirs(PROCESSING)

        if os.path.exists(ARCHIVE):
            os.rename(ARCHIVE, backup_archive)
            archive_saved = True
        with tarfile.open(ARCHIVE, "w:gz") as tf:
            for relpath in dynamic:
                tf.add(os.path.join(source, relpath), arcname=relpath)

        if os.path.exists(CLEAN_ZIP):
            os.rename(CLEAN_ZIP, backup_zip)
            zip_saved = True

        env = os.environ.copy()
        env["PYTHONPATH"] = hooks + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
        env["ORGANIZE_LOCK_LOG"] = lock_log
        result = subprocess.run(
            ["python3", SCRIPT], cwd="/home/user", env=env,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
        )
        assert result.returncode == 0, f"organize.py failed on dynamic inputs:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"

        expected_sources = {os.path.realpath(os.path.join(PROCESSING, rel)) for rel in dynamic}
        expected_yamls = set()
        for relpath, original in dynamic.items():
            source_path = os.path.join(PROCESSING, relpath)
            output_rel = os.path.join(os.path.dirname(relpath), "asset_" + os.path.splitext(os.path.basename(relpath))[0] + ".yaml")
            output_path = os.path.join(PROCESSING, output_rel)
            expected_yamls.add(os.path.realpath(output_path))
            assert not os.path.exists(source_path), f"organize.py did not delete {source_path}."
            assert os.path.isfile(output_path), f"organize.py did not create {output_path}."
            with open(output_path, "rb") as f:
                actual = load_yaml_bytes(f.read(), output_path)
            expected = dict(original)
            expected["processed"] = True
            assert actual == expected, f"Incorrect dynamically generated YAML in {output_path}: expected {expected}, got {actual}."

        found_json = []
        found_yaml = set()
        for root, dirs, files in os.walk(PROCESSING):
            for filename in files:
                path = os.path.realpath(os.path.join(root, filename))
                if filename.endswith(".json"):
                    found_json.append(path)
                elif filename.endswith(".yaml"):
                    found_yaml.add(path)
        assert not found_json, f"Dynamic run left JSON files behind: {found_json}"
        assert found_yaml == expected_yamls, f"Dynamic run produced the wrong YAML files: {found_yaml}"

        events = []
        if os.path.exists(lock_log):
            with open(lock_log, "r", encoding="utf-8") as f:
                events = [json.loads(line) for line in f if line.strip()]
        for source_path in expected_sources:
            relevant = [e for e in events if os.path.realpath(e.get("path", "")) == source_path]
            locks = [e for e in relevant if e.get("kind") == "LOCK" and (int(e.get("op", 0)) & fcntl.LOCK_EX)]
            assert locks, f"organize.py did not successfully acquire an exclusive flock on {source_path}. Events: {relevant}"
            first_access = next((e for e in relevant if e.get("kind") in ("LOCK", "READ")), None)
            assert first_access and first_access.get("kind") == "LOCK", f"organize.py read {source_path} before acquiring its exclusive lock. Events: {relevant}"
    finally:
        shutil.rmtree(PROCESSING, ignore_errors=True)
        if processing_saved:
            os.rename(backup_processing, PROCESSING)
        if os.path.exists(ARCHIVE):
            os.remove(ARCHIVE)
        if archive_saved:
            os.rename(backup_archive, ARCHIVE)
        if os.path.exists(CLEAN_ZIP):
            os.remove(CLEAN_ZIP)
        if zip_saved:
            os.rename(backup_zip, CLEAN_ZIP)
        shutil.rmtree(work, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
