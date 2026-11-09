#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import gzip
import struct
import shutil
import subprocess
import tempfile
import uuid
import pytest

SUMMARY_FILE = "/home/user/config_summary.json"
BASE_DIR = "/home/user/config_backups"


def parse_ccf_stream(f):
    try:
        header = f.read(10)
        if len(header) < 10:
            return None
        magic, timestamp, entry_count = struct.unpack("<4s I H", header)
        if magic != b"CCF1":
            return None

        target_version = None
        for _ in range(entry_count):
            key_len_data = f.read(2)
            if len(key_len_data) < 2:
                break
            key_len = struct.unpack("<H", key_len_data)[0]
            key = f.read(key_len).decode("utf-8", errors="replace")

            val_len_data = f.read(4)
            if len(val_len_data) < 4:
                break
            val_len = struct.unpack("<I", val_len_data)[0]
            val = f.read(val_len).decode("utf-8", errors="replace")

            if key == "target_version":
                target_version = val

        return timestamp, target_version
    except (struct.error, OSError, EOFError):
        return None


def compute_expected_summary():
    expected = {}
    if not os.path.exists(BASE_DIR):
        return expected

    for server_name in os.listdir(BASE_DIR):
        server_dir = os.path.join(BASE_DIR, server_name)
        if not os.path.isdir(server_dir):
            continue

        latest_ts = -1
        latest_version = None

        for filename in os.listdir(server_dir):
            filepath = os.path.join(server_dir, filename)
            if not os.path.isfile(filepath):
                continue

            parsed = None
            if filename.endswith(".ccf.gz"):
                try:
                    with gzip.open(filepath, "rb") as f:
                        parsed = parse_ccf_stream(f)
                except Exception:
                    continue
            elif filename.endswith(".ccf"):
                try:
                    with open(filepath, "rb") as f:
                        parsed = parse_ccf_stream(f)
                except Exception:
                    continue

            if parsed:
                ts, version = parsed
                if version is not None and ts > latest_ts:
                    latest_ts = ts
                    latest_version = version

        if latest_version is not None:
            expected[server_name] = {
                "latest_timestamp": latest_ts,
                "target_version": latest_version,
            }

    return expected


def test_summary_file_exists():
    assert os.path.exists(SUMMARY_FILE), f"The summary file {SUMMARY_FILE} does not exist."
    assert os.path.isfile(SUMMARY_FILE), f"The path {SUMMARY_FILE} is not a file."


def test_summary_file_content():
    assert os.path.exists(SUMMARY_FILE), f"The summary file {SUMMARY_FILE} does not exist."

    with open(SUMMARY_FILE, "r", encoding="utf-8") as f:
        try:
            actual_data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse {SUMMARY_FILE} as JSON: {e}")

    expected_data = compute_expected_summary()
    assert isinstance(actual_data, dict), "The JSON root must be an object (dictionary)."

    missing_servers = set(expected_data.keys()) - set(actual_data.keys())
    assert not missing_servers, f"Missing servers in summary: {missing_servers}"

    extra_servers = set(actual_data.keys()) - set(expected_data.keys())
    assert not extra_servers, f"Unexpected servers in summary: {extra_servers}"

    for server, expected_info in expected_data.items():
        actual_info = actual_data[server]
        assert isinstance(actual_info, dict), f"Value for {server} must be an object."
        assert "latest_timestamp" in actual_info, f"Missing 'latest_timestamp' for {server}"
        assert "target_version" in actual_info, f"Missing 'target_version' for {server}"
        assert actual_info["latest_timestamp"] == expected_info["latest_timestamp"], \
            f"Incorrect latest_timestamp for {server}. Expected {expected_info['latest_timestamp']}, got {actual_info['latest_timestamp']}."
        assert actual_info["target_version"] == expected_info["target_version"], \
            f"Incorrect target_version for {server}. Expected {expected_info['target_version']}, got {actual_info['target_version']}."


def write_ccf(path, timestamp, entries, magic=b"CCF1", compressed=False):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    opener = gzip.open if compressed else open
    with opener(path, "wb") as f:
        f.write(struct.pack("<4sIH", magic, timestamp, len(entries)))
        for key, value in entries.items():
            kb = key.encode("utf-8")
            vb = value.encode("utf-8")
            f.write(struct.pack("<H", len(kb)))
            f.write(kb)
            f.write(struct.pack("<I", len(vb)))
            f.write(vb)


def find_python_scripts():
    scripts = []
    for root, dirs, files in os.walk("/home/user"):
        if os.path.abspath(root).startswith(os.path.abspath(BASE_DIR) + os.sep):
            dirs[:] = []
            continue
        dirs[:] = [d for d in dirs if d not in {"__pycache__", ".cache", ".local"}]
        for name in files:
            path = os.path.join(root, name)
            if name.endswith(".py") and os.path.isfile(path):
                scripts.append(path)
    return sorted(scripts, key=lambda p: os.path.getmtime(p), reverse=True)


def make_dynamic_fixtures(alpha, beta, alpha_version, beta_version):
    shutil.rmtree(BASE_DIR, ignore_errors=True)
    os.makedirs(BASE_DIR)

    alpha_dir = os.path.join(BASE_DIR, "region-one", "archive", alpha)
    beta_dir = os.path.join(BASE_DIR, "region-two", "deeper", beta)

    write_ccf(os.path.join(alpha_dir, "old.ccf"), 101, {"target_version": "obsolete"})
    write_ccf(os.path.join(alpha_dir, "latest.ccf.gz"), 901,
              {"other": "x", "target_version": alpha_version}, compressed=True)
    write_ccf(os.path.join(alpha_dir, "bad-magic.ccf"), 9999,
              {"target_version": "must-not-win"}, magic=b"BAD1")
    write_ccf(os.path.join(alpha_dir, "no-target.ccf"), 10000, {"other": "ignored"})

    write_ccf(os.path.join(beta_dir, "latest.ccf"), 802,
              {"target_version": beta_version, "setting": "yes"})
    write_ccf(os.path.join(beta_dir, "older.ccf.gz"), 701,
              {"target_version": "old-beta"}, compressed=True)
    with open(os.path.join(beta_dir, "corrupt.ccf.gz"), "wb") as f:
        f.write(b"not gzip data")
    with open(os.path.join(beta_dir, "truncated.ccf"), "wb") as f:
        f.write(b"CCF1\x01")

    return {
        alpha: {"latest_timestamp": 901, "target_version": alpha_version},
        beta: {"latest_timestamp": 802, "target_version": beta_version},
    }


def validate_dynamic_output(expected):
    assert os.path.isfile(SUMMARY_FILE), "The script did not create config_summary.json"
    with open(SUMMARY_FILE, "r", encoding="utf-8") as f:
        actual = json.load(f)
    assert isinstance(actual, dict), "The dynamically generated summary is not a JSON object"
    assert set(actual) == set(expected), f"Dynamic server set is wrong: {actual}"
    for server, info in expected.items():
        assert isinstance(actual[server], dict)
        assert actual[server].get("latest_timestamp") == info["latest_timestamp"]
        assert actual[server].get("target_version") == info["target_version"]


def test_script_executes_with_required_io_and_atomic_write():
    scripts = find_python_scripts()
    assert scripts, "No Python script was found under /home/user"

    saved_root = tempfile.mkdtemp(prefix="ccf-verifier-save-")
    saved_backups = os.path.join(saved_root, "config_backups")
    os.rename(BASE_DIR, saved_backups)
    with open(SUMMARY_FILE, "rb") as f:
        saved_summary = f.read()

    hook_dir = tempfile.mkdtemp(prefix="ccf-hooks-")
    event_file = os.path.join(hook_dir, "events.jsonl")
    hook = r'''
import os, json
_EVENT_FILE = os.environ.get("CCF_EVENT_FILE")

def _event(kind, **values):
    try:
        with open(_EVENT_FILE, "a", encoding="utf-8") as out:
            out.write(json.dumps({"kind": kind, **values}) + "\n")
    except Exception:
        pass

import mmap as _mmap
_original_mmap = _mmap.mmap
def _tracked_mmap(fileno, *args, **kwargs):
    path = ""
    try:
        path = os.readlink("/proc/self/fd/%s" % fileno)
    except Exception:
        pass
    _event("mmap", path=path)
    return _original_mmap(fileno, *args, **kwargs)
_mmap.mmap = _tracked_mmap

import gzip as _gzip
_original_gzip_file = _gzip.GzipFile
class _TrackedGzipFile(_original_gzip_file):
    def __init__(self, filename=None, mode=None, *args, **kwargs):
        shown = os.fspath(filename) if isinstance(filename, (str, bytes, os.PathLike)) else ""
        _event("gzip", path=str(shown), mode=str(mode))
        super().__init__(filename, mode, *args, **kwargs)
    def read(self, size=-1):
        if size is None or size < 0:
            _event("gzip_unbounded_read", path=str(getattr(self, "name", "")))
            raise RuntimeError("gzip input must be streamed with bounded reads")
        return super().read(size)
_gzip.GzipFile = _TrackedGzipFile

def _no_decompress(*args, **kwargs):
    _event("gzip_decompress")
    raise RuntimeError("gzip.decompress loads the entire file instead of streaming")
_gzip.decompress = _no_decompress

_original_replace = os.replace
_original_rename = os.rename
def _tracked_replace(src, dst, *args, **kwargs):
    _event("atomic", src=os.path.abspath(os.fspath(src)), dst=os.path.abspath(os.fspath(dst)))
    return _original_replace(src, dst, *args, **kwargs)
def _tracked_rename(src, dst, *args, **kwargs):
    _event("atomic", src=os.path.abspath(os.fspath(src)), dst=os.path.abspath(os.fspath(dst)))
    return _original_rename(src, dst, *args, **kwargs)
os.replace = _tracked_replace
os.rename = _tracked_rename
'''
    with open(os.path.join(hook_dir, "sitecustomize.py"), "w", encoding="utf-8") as f:
        f.write(hook)

    token = uuid.uuid4().hex
    alpha = "alpha-" + token[:10]
    beta = "beta-" + token[10:20]
    alpha_version = "release-" + token[20:]
    beta_version = "build-" + token[:16]
    failures = []

    try:
        for script in scripts:
            expected = make_dynamic_fixtures(alpha, beta, alpha_version, beta_version)
            if os.path.exists(SUMMARY_FILE):
                os.unlink(SUMMARY_FILE)
            open(event_file, "w").close()

            env = os.environ.copy()
            env["CCF_EVENT_FILE"] = event_file
            env["PYTHONPATH"] = hook_dir + os.pathsep + env.get("PYTHONPATH", "")
            try:
                result = subprocess.run(
                    ["python3", script], cwd=os.path.dirname(script) or "/home/user",
                    env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                    text=True, timeout=20
                )
                validate_dynamic_output(expected)
                with open(event_file, "r", encoding="utf-8") as f:
                    events = [json.loads(line) for line in f if line.strip()]

                assert result.returncode == 0, result.stderr
                assert any(e.get("kind") == "mmap" and e.get("path", "").endswith(".ccf")
                           and e.get("path", "").startswith(BASE_DIR + os.sep) for e in events), \
                    "Raw CCF files were not read using mmap"
                assert any(e.get("kind") == "gzip" and e.get("path", "").endswith(".ccf.gz")
                           for e in events), "Gzip files were not opened as gzip streams"
                assert not any(e.get("kind") in {"gzip_unbounded_read", "gzip_decompress"}
                               for e in events), "A gzip file was loaded wholesale instead of streamed"
                atomic = [e for e in events if e.get("kind") == "atomic"
                          and e.get("dst") == SUMMARY_FILE]
                assert atomic, "The final summary was not installed with an atomic rename/replace"
                assert any(os.path.dirname(e.get("src", "")) == os.path.dirname(SUMMARY_FILE)
                           and e.get("src") != SUMMARY_FILE for e in atomic), \
                    "The atomic temporary file was not in the summary's directory"
                return
            except Exception as exc:
                stderr = ""
                if "result" in locals():
                    stderr = result.stderr[-1000:]
                failures.append(f"{script}: {exc}; stderr={stderr}")

        pytest.fail("No discovered Python script satisfied the required behavior and I/O strategy:\n" +
                    "\n".join(failures))
    finally:
        shutil.rmtree(BASE_DIR, ignore_errors=True)
        os.rename(saved_backups, BASE_DIR)
        with open(SUMMARY_FILE, "wb") as f:
            f.write(saved_summary)
        shutil.rmtree(saved_root, ignore_errors=True)
        shutil.rmtree(hook_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
