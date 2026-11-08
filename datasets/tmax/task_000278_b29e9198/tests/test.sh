#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import hashlib
import subprocess

def test_script_exists_and_atomic():
    script_path = "/home/user/artifact_watcher.py"
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    with open(script_path, "r") as f:
        code = f.read()

    # Check for atomic replace pattern
    assert any(x in code for x in ["os.replace", "shutil.move", "os.rename"]), (
        "Script does not appear to use an atomic file replacement method "
        "(os.replace, shutil.move, or os.rename)."
    )

def test_processed_files_exist():
    processed_dir = "/home/user/repo/processed/"
    files = ["file1.bin", "file2.bin", "file3.bin"]
    for file in files:
        file_path = os.path.join(processed_dir, file)
        assert os.path.exists(file_path), f"File {file} was not moved to {processed_dir}."

def test_manifest_contents():
    manifest_path = "/home/user/repo/manifest.json"
    assert os.path.exists(manifest_path), f"Manifest {manifest_path} does not exist."

    with open(manifest_path, "r") as f:
        try:
            manifest = json.load(f)
        except json.JSONDecodeError:
            assert False, "manifest.json is not valid JSON."

    expected_hashes = {
        "file1.bin": hashlib.sha256(b"alpha").hexdigest(),
        "file2.bin": hashlib.sha256(b"beta").hexdigest(),
        "file3.bin": hashlib.sha256(b"gamma").hexdigest(),
    }

    for filename, expected_hash in expected_hashes.items():
        assert filename in manifest, f"{filename} is missing from manifest.json."
        assert manifest[filename] == expected_hash, f"Hash for {filename} is incorrect in manifest.json."

def test_process_exited():
    # Check if artifact_watcher.py is still running
    try:
        result = subprocess.run(["pgrep", "-f", "artifact_watcher.py"], capture_output=True, text=True)
        # If result.returncode == 0, it found a process.
        assert result.returncode != 0, "The artifact_watcher.py process is still running; it did not shut down gracefully."
    except FileNotFoundError:
        # pgrep not available, fallback to ps
        result = subprocess.run(["ps", "aux"], capture_output=True, text=True)
        lines = [line for line in result.stdout.splitlines() if "artifact_watcher.py" in line and "grep" not in line and "pytest" not in line]
        assert len(lines) == 0, "The artifact_watcher.py process is still running; it did not shut down gracefully."
TEST_EOF

cat << 'PROBE_EOF' > /tmp/test_watcher_behavior.py
import hashlib
import json
import os
import secrets
import subprocess
import sys
import time
from pathlib import Path

SCRIPT = Path("/home/user/artifact_watcher.py")
REPO = Path("/home/user/repo")
INCOMING = REPO / "incoming"
PROCESSED = REPO / "processed"
MANIFEST = REPO / "manifest.json"
PROBE_DIR = Path("/tmp/watcher_probe")
PROBE_LOG = Path("/tmp/watcher_atomic_ops.jsonl")

assert SCRIPT.is_file(), "artifact_watcher.py is not a regular file"
INCOMING.mkdir(parents=True, exist_ok=True)
PROCESSED.mkdir(parents=True, exist_ok=True)
assert MANIFEST.is_file(), "manifest.json is missing"

# Remove only control-file remnants so this run can exercise shutdown itself.
for path in (INCOMING / "SHUTDOWN", PROCESSED / "SHUTDOWN"):
    try:
        path.unlink()
    except FileNotFoundError:
        pass

with MANIFEST.open() as f:
    before = json.load(f)
assert isinstance(before, dict), "manifest.json must contain a JSON object"
assert "SHUTDOWN" not in before, "SHUTDOWN must not be recorded in the manifest"

PROBE_DIR.mkdir(exist_ok=True)
PROBE_LOG.unlink(missing_ok=True)
(PROBE_DIR / "sitecustomize.py").write_text(r'''
import json
import os
import shutil

_log_path = os.environ.get("WATCHER_ATOMIC_LOG")
_original_replace = os.replace
_original_rename = os.rename
_original_move = shutil.move

def _record(kind, src, dst):
    if not _log_path:
        return
    try:
        entry = {"kind": kind, "src": os.fspath(src), "dst": os.fspath(dst)}
        with open(_log_path, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry) + "\\n")
    except Exception:
        pass

def replace(src, dst, *args, **kwargs):
    result = _original_replace(src, dst, *args, **kwargs)
    _record("os.replace", src, dst)
    return result

def rename(src, dst, *args, **kwargs):
    result = _original_rename(src, dst, *args, **kwargs)
    _record("os.rename", src, dst)
    return result

def move(src, dst, *args, **kwargs):
    result = _original_move(src, dst, *args, **kwargs)
    _record("shutil.move", src, dst)
    return result

os.replace = replace
os.rename = rename
shutil.move = move
''', encoding="utf-8")

env = os.environ.copy()
env["PYTHONPATH"] = str(PROBE_DIR) + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
env["WATCHER_ATOMIC_LOG"] = str(PROBE_LOG)

proc = subprocess.Popen(
    [sys.executable, str(SCRIPT)],
    env=env,
    stdout=subprocess.DEVNULL,
    stderr=subprocess.PIPE,
    text=True,
)

created = {}
try:
    time.sleep(1.25)
    assert proc.poll() is None, "watcher exited before any new file was created"

    token = secrets.token_hex(8)
    first = {
        f"audit_{token}_a.bin": secrets.token_bytes(137),
        f"audit_{token}_b.dat": secrets.token_bytes(911),
    }
    for name, data in first.items():
        (INCOMING / name).write_bytes(data)
        created[name] = data

    deadline = time.time() + 12
    while time.time() < deadline:
        if all((PROCESSED / name).is_file() for name in first):
            break
        assert proc.poll() is None, "watcher exited while processing the first batch"
        time.sleep(0.1)
    assert all((PROCESSED / name).is_file() for name in first), "watcher did not process the first batch"

    # A second wave proves that the process continues watching after initial startup.
    second = {f"audit_{token}_later.bin": secrets.token_bytes(2049)}
    time.sleep(0.4)
    for name, data in second.items():
        (INCOMING / name).write_bytes(data)
        created[name] = data

    deadline = time.time() + 12
    while time.time() < deadline:
        try:
            with MANIFEST.open() as f:
                current = json.load(f)
        except (json.JSONDecodeError, OSError) as exc:
            raise AssertionError(f"manifest became unreadable during watcher updates: {exc}")
        complete = all(
            (PROCESSED / name).is_file()
            and current.get(name) == hashlib.sha256(data).hexdigest()
            for name, data in created.items()
        )
        if complete:
            break
        assert proc.poll() is None, "watcher exited before processing all new files"
        time.sleep(0.05)
    assert complete, "watcher did not process dynamically generated files correctly"

    (INCOMING / "SHUTDOWN").write_bytes(b"")
    try:
        returncode = proc.wait(timeout=8)
    except subprocess.TimeoutExpired:
        raise AssertionError("watcher did not exit after SHUTDOWN appeared")
    stderr = proc.stderr.read() if proc.stderr else ""
    assert returncode == 0, f"watcher did not exit cleanly (code {returncode}): {stderr}"

    with MANIFEST.open() as f:
        final = json.load(f)
    for key, value in before.items():
        assert final.get(key) == value, f"watcher failed to preserve existing manifest entry {key}"
    for name, data in created.items():
        assert (PROCESSED / name).read_bytes() == data, f"processed contents changed for {name}"
        assert final.get(name) == hashlib.sha256(data).hexdigest(), f"incorrect checksum for {name}"
        assert not (INCOMING / name).exists(), f"{name} was not moved out of incoming"
    assert "SHUTDOWN" not in final, "SHUTDOWN was incorrectly added to the manifest"
    assert (INCOMING / "SHUTDOWN").is_file(), "SHUTDOWN was incorrectly moved or removed"
    assert not (PROCESSED / "SHUTDOWN").exists(), "SHUTDOWN was incorrectly curated"

    operations = []
    if PROBE_LOG.exists():
        for line in PROBE_LOG.read_text(encoding="utf-8").splitlines():
            operations.append(json.loads(line))
    manifest_abs = os.path.abspath(MANIFEST)
    atomic_updates = [
        op for op in operations
        if os.path.abspath(op["dst"]) == manifest_abs
        and os.path.abspath(op["src"]) != manifest_abs
        and os.path.dirname(os.path.abspath(op["src"])) == os.path.dirname(manifest_abs)
        and op["kind"] in {"os.replace", "os.rename", "shutil.move"}
    ]
    assert atomic_updates, "no successful atomic replacement of manifest.json was executed"
finally:
    if proc.poll() is None:
        proc.kill()
        proc.wait()
PROBE_EOF

status=0
python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 || status=1
if [ "$status" -eq 0 ]; then
    python3 /tmp/test_watcher_behavior.py 2>&1 || status=1
fi

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
