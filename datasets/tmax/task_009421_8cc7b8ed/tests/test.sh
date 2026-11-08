#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import secrets
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

RAW_DATASET_DIR = "/home/user/raw_dataset"
CLEAN_DATASET_DIR = "/home/user/clean_dataset"
MANIFEST_FILE = "/home/user/backup_manifest.csv"
TRACE_DIR = "/tmp/verifier_atomic_trace"
TRACE_FILE = "/tmp/verifier_atomic_events.jsonl"

VALID_FILES = [
    ("scan_root.dat", 20, b"BRAN" + b"\x00" * 16),
    ("subject1/scan1.dat", 8, b"BRAN" + b"\x01\x02\x03\x04"),
    ("subject2/sessionA/scanA.dat", 14, b"BRAN" + b"\xFF" * 10),
    ("subject3/scan3.dat", 104, b"BRAN" + b"\x0A" * 100),
]

INVALID_FILES = [
    "subject1/corrupt.dat",
    "subject2/sessionB/short.dat",
]

EXPECTED = {}
PREP_ERROR = None
SELECTED_SCRIPT = None


def norm(path):
    return os.path.normcase(os.path.realpath(os.path.abspath(path)))


def discover_scripts():
    roots = ["/home", "/root", "/tmp", "/workspace", "/app"]
    seen = set()
    candidates = []
    excluded = {
        norm(__file__),
        norm(os.path.join(TRACE_DIR, "sitecustomize.py")),
    }

    for root in roots:
        if not os.path.isdir(root):
            continue
        for current, dirs, files in os.walk(root):
            current_norm = norm(current)
            if current_norm.startswith(norm(RAW_DATASET_DIR)) or current_norm.startswith(norm(CLEAN_DATASET_DIR)):
                dirs[:] = []
                continue
            if current_norm.startswith(norm("/tests")) or current_norm.startswith(norm(TRACE_DIR)):
                dirs[:] = []
                continue
            dirs[:] = [d for d in dirs if d not in {".git", "__pycache__", ".cache", "node_modules"}]
            for name in files:
                if not name.endswith(".py"):
                    continue
                path = os.path.join(current, name)
                real = norm(path)
                if real in excluded or real in seen or not os.path.isfile(path):
                    continue
                seen.add(real)
                try:
                    text = Path(path).read_text(encoding="utf-8", errors="ignore")
                    st = os.stat(path)
                except OSError:
                    continue
                # The requested script necessarily identifies the fixed source,
                # destination, and manifest locations in some form.
                score = sum(token in text for token in ("raw_dataset", "clean_dataset", "backup_manifest"))
                if score == 3:
                    candidates.append((st.st_mtime_ns, path))

    candidates.sort(reverse=True)
    return [path for _, path in candidates]


def install_atomic_tracer():
    shutil.rmtree(TRACE_DIR, ignore_errors=True)
    os.makedirs(TRACE_DIR)
    Path(os.path.join(TRACE_DIR, "sitecustomize.py")).write_text(r'''
import hashlib
import json
import os

_TRACE = os.environ.get("ATOMIC_TRACE_FILE")
_orig_rename = os.rename
_orig_replace = os.replace


def _resolved(value, dir_fd=None):
    try:
        value = os.fsdecode(value)
        if os.path.isabs(value):
            return os.path.realpath(value)
        if dir_fd is not None:
            try:
                base = os.readlink("/proc/self/fd/%d" % dir_fd)
                return os.path.realpath(os.path.join(base, value))
            except Exception:
                pass
        return os.path.realpath(os.path.abspath(value))
    except Exception:
        return None


def _wrapped(operation, original):
    def call(src, dst, *args, **kwargs):
        src_fd = kwargs.get("src_dir_fd")
        dst_fd = kwargs.get("dst_dir_fd")
        source = _resolved(src, src_fd)
        destination = _resolved(dst, dst_fd)
        digest = None
        size = None
        existed = False
        try:
            existed = os.path.isfile(source)
            if existed:
                data = open(source, "rb").read()
                digest = hashlib.sha256(data).hexdigest()
                size = len(data)
        except Exception:
            pass

        result = original(src, dst, *args, **kwargs)
        if _TRACE:
            event = {
                "operation": operation,
                "source": source,
                "destination": destination,
                "source_existed": existed,
                "sha256": digest,
                "size": size,
            }
            try:
                with open(_TRACE, "a", encoding="utf-8") as log:
                    log.write(json.dumps(event, sort_keys=True) + "\n")
            except Exception:
                pass
        return result
    return call

os.rename = _wrapped("rename", _orig_rename)
os.replace = _wrapped("replace", _orig_replace)
''', encoding="utf-8")


def collect_expected():
    expected = {}
    for root, _, files in os.walk(RAW_DATASET_DIR):
        for name in files:
            if not name.endswith(".dat"):
                continue
            source = os.path.join(root, name)
            rel = os.path.relpath(source, RAW_DATASET_DIR).replace(os.sep, "/")
            with open(source, "rb") as f:
                data = f.read()
            if data[:4] == b"BRAN":
                expected[rel] = data
    return expected


def read_manifest_lines():
    if not os.path.isfile(MANIFEST_FILE):
        return None
    with open(MANIFEST_FILE, "r", encoding="utf-8") as f:
        content = f.read().strip()
    return [line.strip() for line in content.splitlines() if line.strip()]


def output_is_correct(expected):
    if not os.path.isdir(CLEAN_DATASET_DIR):
        return False
    actual = {}
    for root, _, files in os.walk(CLEAN_DATASET_DIR):
        for name in files:
            path = os.path.join(root, name)
            rel = os.path.relpath(path, CLEAN_DATASET_DIR).replace(os.sep, "/")
            with open(path, "rb") as f:
                actual[rel] = f.read()
    if actual != expected:
        return False
    lines = [f"{rel},{len(expected[rel])}" for rel in sorted(expected)]
    return read_manifest_lines() == lines


def atomic_trace_is_correct(expected):
    try:
        events = [json.loads(line) for line in Path(TRACE_FILE).read_text(encoding="utf-8").splitlines() if line.strip()]
    except (OSError, ValueError):
        return False

    for rel, data in expected.items():
        destination = norm(os.path.join(CLEAN_DATASET_DIR, *rel.split("/")))
        digest = hashlib.sha256(data).hexdigest()
        matching = []
        for event in events:
            if not event.get("destination") or norm(event["destination"]) != destination:
                continue
            source = event.get("source")
            if not source:
                continue
            if norm(source) == destination:
                continue
            if os.path.dirname(norm(source)) != os.path.dirname(destination):
                continue
            if event.get("source_existed") and event.get("sha256") == digest and event.get("size") == len(data):
                matching.append(event)
        if not matching:
            return False
    return True


def prepare_and_execute():
    global EXPECTED, PREP_ERROR, SELECTED_SCRIPT
    try:
        token = secrets.token_hex(12)
        probes = {
            f"verifier_{token}/deep/valid_alpha_{token}.dat": b"BRAN" + secrets.token_bytes(37),
            f"verifier_{token}/valid_empty_payload_{token}.dat": b"BRAN",
            f"root_valid_{token}.dat": b"BRAN" + secrets.token_bytes(91),
            f"verifier_{token}/deep/corrupt_{token}.dat": b"NOPE" + secrets.token_bytes(29),
            f"verifier_{token}/short_{token}.dat": b"BRA",
        }
        for rel, data in probes.items():
            path = os.path.join(RAW_DATASET_DIR, *rel.split("/"))
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "wb") as f:
                f.write(data)

        EXPECTED = collect_expected()
        scripts = discover_scripts()
        assert scripts, "No Python script implementing the requested dataset processing was found."
        install_atomic_tracer()

        failures = []
        for script in scripts:
            shutil.rmtree(CLEAN_DATASET_DIR, ignore_errors=True)
            try:
                os.remove(MANIFEST_FILE)
            except FileNotFoundError:
                pass
            try:
                os.remove(TRACE_FILE)
            except FileNotFoundError:
                pass

            env = os.environ.copy()
            env["PYTHONPATH"] = TRACE_DIR + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
            env["ATOMIC_TRACE_FILE"] = TRACE_FILE
            result = subprocess.run(
                [sys.executable, script],
                cwd=os.path.dirname(script) or "/home/user",
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=60,
            )
            if result.returncode != 0:
                failures.append(f"{script}: exited {result.returncode}")
                continue
            if not output_is_correct(EXPECTED):
                failures.append(f"{script}: output or manifest was incorrect")
                continue
            if not atomic_trace_is_correct(EXPECTED):
                failures.append(f"{script}: copies were not completed by same-directory temporary-file renames")
                continue
            SELECTED_SCRIPT = script
            return

        raise AssertionError("No discovered script passed recursive, manifest, and atomic-copy checks. " + "; ".join(failures))
    except Exception as exc:
        PREP_ERROR = str(exc)


prepare_and_execute()


def test_script_was_found_and_executed():
    assert PREP_ERROR is None, PREP_ERROR
    assert SELECTED_SCRIPT is not None
    assert os.path.isfile(SELECTED_SCRIPT)
    assert SELECTED_SCRIPT.endswith(".py")


def test_clean_dataset_exists():
    assert os.path.isdir(CLEAN_DATASET_DIR), f"Directory {CLEAN_DATASET_DIR} does not exist."


@pytest.mark.parametrize("rel_path, size, content", VALID_FILES)
def test_valid_files_copied(rel_path, size, content):
    dest_path = os.path.join(CLEAN_DATASET_DIR, rel_path)
    assert os.path.isfile(dest_path), f"Valid file {rel_path} was not copied to {CLEAN_DATASET_DIR}."
    assert os.path.getsize(dest_path) == size, f"File {rel_path} size mismatch. Expected {size}, got {os.path.getsize(dest_path)}."
    with open(dest_path, "rb") as f:
        assert f.read() == content, f"File {rel_path} content mismatch."


@pytest.mark.parametrize("rel_path", INVALID_FILES)
def test_invalid_files_not_copied(rel_path):
    dest_path = os.path.join(CLEAN_DATASET_DIR, rel_path)
    assert not os.path.exists(dest_path), f"Invalid file {rel_path} should not have been copied."


def test_all_and_only_recursive_valid_files_copied():
    actual = {}
    for root, _, files in os.walk(CLEAN_DATASET_DIR):
        for name in files:
            path = os.path.join(root, name)
            rel = os.path.relpath(path, CLEAN_DATASET_DIR).replace(os.sep, "/")
            with open(path, "rb") as f:
                actual[rel] = f.read()
    assert actual == EXPECTED


def test_manifest_file():
    assert os.path.isfile(MANIFEST_FILE), f"Manifest file {MANIFEST_FILE} does not exist."
    expected_lines = [
        "scan_root.dat,20",
        "subject1/scan1.dat,8",
        "subject2/sessionA/scanA.dat,14",
        "subject3/scan3.dat,104",
    ]
    actual_lines = read_manifest_lines()
    for line in expected_lines:
        assert line in actual_lines

    complete_expected = [f"{rel},{len(EXPECTED[rel])}" for rel in sorted(EXPECTED)]
    assert actual_lines == complete_expected, f"Manifest file content mismatch. Expected:\n{complete_expected}\nGot:\n{actual_lines}"


def test_atomic_copy_trace():
    assert atomic_trace_is_correct(EXPECTED), "Every valid file must be written to a same-directory temporary file and renamed to its final path."


def test_no_tmp_files_left():
    for root, dirs, files in os.walk(CLEAN_DATASET_DIR):
        for file in files:
            assert not file.endswith(".tmp"), f"Temporary file {file} was left behind in {root}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
