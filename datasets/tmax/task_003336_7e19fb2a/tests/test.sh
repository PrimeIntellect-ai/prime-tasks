#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import json
import os
import re
import secrets
import subprocess
import sys
from collections import Counter
from pathlib import Path

import pytest

SCRIPT_PATH = "/home/user/curate.py"
VENDOR_UNIX = Path("/app/vendor/filelock-3.12.2/src/filelock/_unix.py")


def run_curator(input_dir, output_dir, log_file, env=None):
    return subprocess.run(
        [sys.executable, SCRIPT_PATH, "--input", str(input_dir), "--output", str(output_dir), "--log", str(log_file)],
        capture_output=True,
        text=True,
        timeout=12,
        env=env,
    )


def flag_attributes(source):
    tree = ast.parse(source)
    return {
        node.attr
        for node in ast.walk(tree)
        if isinstance(node, ast.Attribute)
        and isinstance(node.value, ast.Name)
        and node.value.id == "os"
    }


def test_filelock_fixed_and_installed():
    """Verify both the vendored source and the installed distribution."""
    assert VENDOR_UNIX.is_file(), "Vendored filelock Unix implementation is missing."
    vendor_flags = flag_attributes(VENDOR_UNIX.read_text())
    assert "O_EXCLL" not in vendor_flags, "The O_EXCLL typo remains in the vendored source."
    assert "O_EXCL" in vendor_flags, "The vendored source was not fixed to use os.O_EXCL."

    check = r'''
import ast
import importlib.metadata
import inspect
import json
import os
import tempfile
import filelock
import filelock._unix as unix

source = inspect.getsource(unix)
tree = ast.parse(source)
flags = sorted({n.attr for n in ast.walk(tree)
                if isinstance(n, ast.Attribute)
                and isinstance(n.value, ast.Name)
                and n.value.id == "os"})
path = tempfile.mktemp(prefix="installed-filelock-", suffix=".lock")
try:
    lock = filelock.FileLock(path)
    lock.acquire()
finally:
    if os.path.exists(path):
        os.remove(path)
print(json.dumps({
    "version": importlib.metadata.version("filelock"),
    "module": filelock.__file__,
    "flags": flags,
}))
'''
    result = subprocess.run(
        [sys.executable, "-c", check], capture_output=True, text=True, timeout=10, cwd="/tmp"
    )
    assert result.returncode == 0, f"Installed filelock cannot acquire a lock:\n{result.stderr}"
    info = json.loads(result.stdout.strip().splitlines()[-1])
    assert info["version"] == "3.12.2", f"Vendored filelock 3.12.2 is not installed: {info}"
    assert "O_EXCLL" not in info["flags"], "Installed filelock still uses os.O_EXCLL."
    assert "O_EXCL" in info["flags"], "Installed Unix implementation is not the fixed vendored implementation."


def test_curate_script_clean_corpus(tmp_path):
    """Retain the original visible-corpus assertions and verify an actual move."""
    assert os.path.isfile(SCRIPT_PATH), f"Curation script not found at {SCRIPT_PATH}"

    clean_input = "/app/verifier_corpus/clean"
    clean_out = str(tmp_path / "clean_out")
    clean_log = str(tmp_path / "clean_log.csv")

    result = run_curator(clean_input, clean_out, clean_log)
    assert result.returncode == 0, f"Script failed on clean corpus. Stderr:\n{result.stderr}"

    expected_out_dir = os.path.join(clean_out, "abc_v9")
    assert os.path.isdir(expected_out_dir), "Clean bundle 'b1' was not moved to the expected output directory 'abc_v9'."
    assert os.path.isfile(os.path.join(expected_out_dir, "dir", "meta.json")), "Contents of the clean bundle were not preserved."
    assert not os.path.exists(os.path.join(clean_input, "b1")), "Clean bundle was copied instead of moved."

    assert os.path.isfile(clean_log), "Log file was not created for clean corpus."
    with open(clean_log, "r") as f:
        content = f.read().strip()
    assert "abc,9,b1" in content, f"Log file missing expected record for clean bundle. Log content:\n{content}"


def test_curate_script_evil_corpus(tmp_path):
    """Retain the original visible evil-corpus assertions."""
    assert os.path.isfile(SCRIPT_PATH), f"Curation script not found at {SCRIPT_PATH}"

    evil_input = "/app/verifier_corpus/evil"
    evil_out = str(tmp_path / "evil_out")
    evil_log = str(tmp_path / "evil_log.csv")

    result = run_curator(evil_input, evil_out, evil_log)
    assert result.returncode == 0, f"Script crashed or hung on evil corpus. Stderr:\n{result.stderr}"

    if os.path.exists(evil_out):
        moved_files = os.listdir(evil_out)
        assert not moved_files, f"Evil bundles were moved to output directory instead of being rejected: {moved_files}"
    if os.path.exists(evil_log):
        with open(evil_log, "r") as f:
            content = f.read().strip()
        assert not content, f"Log file contains entries for evil bundles:\n{content}"


def install_lock_probe(probe_root, marker):
    package = probe_root / "filelock"
    package.mkdir(parents=True)
    package.joinpath("__init__.py").write_text(r'''
import os
class FileLock:
    def __init__(self, path, *args, **kwargs):
        self.path = os.fspath(path)
        self.fd = None
    def acquire(self, *args, **kwargs):
        marker = os.environ["CURATE_LOCK_MARKER"]
        with open(marker, "a", encoding="utf-8") as stream:
            stream.write(self.path + "\n")
        self.fd = os.open(self.path, os.O_CREAT | os.O_WRONLY | os.O_EXCL)
        return self
    def release(self, *args, **kwargs):
        if self.fd is not None:
            os.close(self.fd)
            self.fd = None
        try:
            os.unlink(self.path)
        except FileNotFoundError:
            pass
    def __enter__(self):
        return self.acquire()
    def __exit__(self, exc_type, exc_value, traceback):
        self.release()
''')


@pytest.mark.parametrize("case_number", range(3))
def test_randomized_hidden_corpora_and_lock_use(tmp_path, case_number):
    """Exercise unpredictable names/metadata, move semantics, evil cases, and FileLock use."""
    assert os.path.isfile(SCRIPT_PATH), f"Curation script not found at {SCRIPT_PATH}"

    token = secrets.token_hex(8)
    input_dir = tmp_path / f"incoming_{token}"
    output_dir = tmp_path / f"curated_{token}"
    log_file = tmp_path / f"audit_{token}.csv"
    input_dir.mkdir()

    clean_name = f"bundle_{secrets.token_hex(5)}"
    uuid = f"u{secrets.token_hex(7)}"
    version = f"{secrets.randbelow(80) + 10}.{secrets.randbelow(1000)}"
    nested = input_dir / clean_name / f"level_{secrets.token_hex(3)}" / f"deep_{secrets.token_hex(3)}"
    nested.mkdir(parents=True)
    metadata = {"UUID": uuid, "version": version, "extra": token}
    (nested / "meta.json").write_text(json.dumps(metadata))
    (input_dir / clean_name / "payload.bin").write_bytes(secrets.token_bytes(37))

    malformed_name = f"malformed_{secrets.token_hex(5)}"
    malformed = input_dir / malformed_name
    malformed.mkdir()
    (malformed / "meta.json").write_text('{"UUID": "broken", "version":')

    missing_name = f"missing_{secrets.token_hex(5)}"
    missing = input_dir / missing_name / "somewhere"
    missing.mkdir(parents=True)
    (missing / "payload.dat").write_text(token)

    loop_name = f"loop_{secrets.token_hex(5)}"
    loop_bundle = input_dir / loop_name
    loop_dir = loop_bundle / "nested"
    loop_dir.mkdir(parents=True)
    (loop_bundle / "meta.json").write_text(json.dumps({"UUID": "reject" + token, "version": "1"}))
    os.symlink(".", loop_dir / f"cycle_{secrets.token_hex(3)}")

    marker = tmp_path / f"lock_marker_{token}"
    probe_root = tmp_path / f"probe_{token}"
    install_lock_probe(probe_root, marker)
    env = os.environ.copy()
    env["CURATE_LOCK_MARKER"] = str(marker)
    env["PYTHONPATH"] = str(probe_root) + os.pathsep + env.get("PYTHONPATH", "")

    result = run_curator(input_dir, output_dir, log_file, env=env)
    assert result.returncode == 0, f"Script failed on randomized corpus. Stderr:\n{result.stderr}"

    expected_name = f"{uuid}_v{version}"
    assert output_dir.is_dir(), "Output directory was not created."
    assert set(os.listdir(output_dir)) == {expected_name}, "Output contains missing, extra, or wrongly named bundles."

    moved = output_dir / expected_name
    assert (moved / nested.relative_to(input_dir / clean_name) / "meta.json").is_file()
    assert (moved / "payload.bin").read_bytes() != b""
    assert not (input_dir / clean_name).exists(), "The clean bundle was copied rather than moved."

    for rejected in (malformed_name, missing_name, loop_name):
        assert (input_dir / rejected).is_dir(), f"Evil bundle {rejected} was not entirely rejected."

    assert log_file.is_file(), "Audit log was not created."
    with log_file.open(newline="") as stream:
        rows = list(csv.reader(stream))
    assert Counter(map(tuple, rows)) == Counter([(uuid, version, clean_name)]), f"Incorrect audit records: {rows}"

    assert marker.is_file(), "curate.py did not acquire a lock through filelock.FileLock."
    lock_events = [line for line in marker.read_text().splitlines() if line.strip()]
    assert lock_events, "curate.py imported filelock but did not acquire its FileLock."
    assert any(str(log_file) in event for event in lock_events), "The acquired FileLock was not associated with the audit log."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
