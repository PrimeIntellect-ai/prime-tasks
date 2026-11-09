#!/bin/bash
mkdir -p /logs/verifier

run_checks() {
    python3 - <<'PY' || return 1
import os
import stat

source = "/home/user/process.rs"
binary = "/home/user/process"

assert os.path.isfile(source), f"Missing Rust source: {source}"
st = os.lstat(binary)
assert stat.S_ISREG(st.st_mode), f"Compiled program is not a regular file: {binary}"
assert os.access(binary, os.X_OK), f"Compiled program is not executable: {binary}"
with open(binary, "rb") as f:
    assert f.read(4) == b"\x7fELF", f"Compiled program is not an ELF executable: {binary}"
PY

    rustc /home/user/process.rs -o /tmp/process_from_source || return 1

    cat > /tmp/exercise_process.py <<'PY' || return 1
import os
import shutil
import subprocess
import sys

DATASET_DIR = "/home/user/dataset"
PROCESSED_DIR = "/home/user/processed"
LINKS_DIR = "/home/user/links"
executable = sys.argv[1]

expected = {}
for root, _, files in os.walk(DATASET_DIR):
    for name in files:
        if not name.endswith(".log"):
            continue
        assert name not in expected, f"Duplicate test basename: {name}"
        path = os.path.join(root, name)
        with open(path, "rb") as f:
            text = f.read().decode("utf-16le")
        expected[name] = text.replace("ERROR_CODE_99", "RESOLVED_01")

shutil.rmtree(PROCESSED_DIR, ignore_errors=True)
shutil.rmtree(LINKS_DIR, ignore_errors=True)
os.makedirs(PROCESSED_DIR)
os.makedirs(LINKS_DIR)

subprocess.run([executable], cwd="/home/user", check=True, timeout=30)

for name, expected_text in expected.items():
    processed = os.path.join(PROCESSED_DIR, name)
    link = os.path.join(LINKS_DIR, name)
    assert os.path.isfile(processed), f"Processed file missing: {processed}"
    assert os.path.isfile(link), f"Link file missing: {link}"
    with open(processed, "rb") as f:
        data = f.read()
    assert b"\x00" not in data, f"File contains null bytes: {processed}"
    try:
        actual = data.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise AssertionError(f"File is not valid UTF-8: {processed}") from exc
    assert actual == expected_text, f"Content mismatch in {processed}"
    proc_stat = os.stat(processed)
    link_stat = os.stat(link)
    assert proc_stat.st_ino == link_stat.st_ino, f"Not a hard link: {link}"
    assert proc_stat.st_dev == link_stat.st_dev, f"Different devices: {link}"
PY

    token="$(python3 -c 'import secrets; print(secrets.token_hex(12))')" || return 1
    export VERIFIER_TOKEN="$token"

    python3 - <<'PY' || return 1
import os

token = os.environ["VERIFIER_TOKEN"]
base = os.path.join("/home/user/dataset", "verifier_" + token, "deep", "nested")
os.makedirs(base, exist_ok=True)
text = f"Dynamic {token}: ERROR_CODE_99 — café — ERROR_CODE_99"
with open(os.path.join(base, f"dynamic_{token}.log"), "wb") as f:
    f.write(text.encode("utf-16le"))
PY

    python3 /tmp/exercise_process.py /home/user/process || return 1

    python3 - <<'PY' || return 1
import os

token = os.environ["VERIFIER_TOKEN"]
base = os.path.join("/home/user/dataset", "verifier_" + token, "second", "level")
os.makedirs(base, exist_ok=True)
text = f"Second unseen input {token}: prefixERROR_CODE_99suffix and λ."
with open(os.path.join(base, f"second_{token}.log"), "wb") as f:
    f.write(text.encode("utf-16le"))
PY

    python3 /tmp/exercise_process.py /tmp/process_from_source || return 1

    cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

EXPECTED_FILES = {
    "file_a.log": "Log entry 1: RESOLVED_01 found.",
    "file_b.log": "No errors here. Just standard text.",
    "file_c.log": "Critical RESOLVED_01 and another RESOLVED_01!"
}

PROCESSED_DIR = "/home/user/processed"
LINKS_DIR = "/home/user/links"

def test_processed_files_exist_and_content():
    """Check that processed files exist, are valid UTF-8, and have correct content."""
    for filename, expected_text in EXPECTED_FILES.items():
        filepath = os.path.join(PROCESSED_DIR, filename)
        assert os.path.isfile(filepath), f"Processed file missing: {filepath}"

        # Read as bytes to check for null bytes (UTF-16 leftover check)
        with open(filepath, "rb") as f:
            content_bytes = f.read()

        assert b'\x00' not in content_bytes, f"File {filepath} contains null bytes, likely not properly converted to UTF-8."

        # Decode as UTF-8
        try:
            content_str = content_bytes.decode("utf-8")
        except UnicodeDecodeError:
            pytest.fail(f"File {filepath} is not valid UTF-8.")

        assert content_str == expected_text, f"Content mismatch in {filepath}. Expected '{expected_text}', got '{content_str}'"

def test_hard_links_exist_and_correct():
    """Check that hard links exist and share the same inode as the processed files."""
    for filename in EXPECTED_FILES.keys():
        processed_path = os.path.join(PROCESSED_DIR, filename)
        link_path = os.path.join(LINKS_DIR, filename)

        assert os.path.isfile(link_path), f"Link file missing: {link_path}"

        stat_proc = os.stat(processed_path)
        stat_link = os.stat(link_path)

        assert stat_proc.st_ino == stat_link.st_ino, f"{link_path} is not a hard link to {processed_path}"
        assert stat_proc.st_dev == stat_link.st_dev, f"{link_path} and {processed_path} are on different devices"
TEST_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 || return 1
}

if run_checks; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
