#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import re
import secrets
import subprocess
import tempfile
import time
from pathlib import Path

import pytest

BINARY = "/home/user/local/bin/inotifywait"
SCRIPT = "/home/user/sanitize_manifest.sh"
SOURCE = "/app/vendor/inotify-tools-3.22.6/src/inotifywait.c"


def test_inotifywait_installed():
    """Test that inotifywait was successfully built and installed."""
    assert os.path.isfile(BINARY), f"Binary {BINARY} is missing."
    assert os.access(BINARY, os.X_OK), f"Binary {BINARY} is not executable."

    result = subprocess.run([BINARY, "--help"], capture_output=True, text=True)
    assert result.returncode == 0, f"inotifywait --help failed with exit code {result.returncode}"


def test_sanitize_manifest_exists():
    """Test that the sanitize_manifest.sh script exists and is executable."""
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} is missing."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."


def test_clean_corpus():
    """Test that the script accepts all clean corpus files and outputs valid UTF-8."""
    clean_dir = "/app/corpora/clean"
    clean_files = glob.glob(os.path.join(clean_dir, "*"))

    if not clean_files:
        pytest.skip("No clean corpus files found.")

    failed_files = []
    for f in clean_files:
        if not os.path.isfile(f):
            continue

        result = subprocess.run([SCRIPT, f], capture_output=True)
        if result.returncode != 0:
            failed_files.append(f"{os.path.basename(f)} (exit code {result.returncode})")
            continue

        try:
            stdout_str = result.stdout.decode("utf-8")
            if not stdout_str.strip():
                failed_files.append(f"{os.path.basename(f)} (empty stdout)")
        except UnicodeDecodeError:
            failed_files.append(f"{os.path.basename(f)} (invalid UTF-8 output)")

    assert not failed_files, f"{len(failed_files)} of {len(clean_files)} clean modified/rejected: {', '.join(failed_files)}"


def test_evil_corpus():
    """Test that the script rejects all evil corpus files and prints nothing to stdout."""
    evil_dir = "/app/corpora/evil"
    evil_files = glob.glob(os.path.join(evil_dir, "*"))

    if not evil_files:
        pytest.skip("No evil corpus files found.")

    failed_files = []
    for f in evil_files:
        if not os.path.isfile(f):
            continue

        result = subprocess.run([SCRIPT, f], capture_output=True)
        if result.returncode == 0:
            failed_files.append(f"{os.path.basename(f)} (exit code 0)")
        elif result.stdout != b"":
            failed_files.append(f"{os.path.basename(f)} (stdout not empty)")

    assert not failed_files, f"{len(failed_files)} of {len(evil_files)} evil bypassed: {', '.join(failed_files)}"


def test_inotifywait_is_built_binary_and_source_is_fixed():
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "inotifywait is not a compiled ELF binary"

    source = Path(SOURCE).read_text(encoding="utf-8")
    assert re.search(r"\bint\s+main\s*\(", source), "inotifywait.c does not contain the repaired main function"
    assert not re.search(r"\bint\s+mian\s*\(", source), "the deliberate mian typo remains in inotifywait.c"


def test_inotifywait_observes_a_real_filesystem_event():
    with tempfile.TemporaryDirectory(prefix="watch-" + secrets.token_hex(6) + "-") as watched:
        proc = subprocess.Popen(
            [BINARY, "-q", "-e", "create", "--format", "%e:%f", watched],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        created = []
        try:
            for _ in range(30):
                time.sleep(0.1)
                if proc.poll() is not None:
                    break
                name = "event-" + secrets.token_hex(8)
                Path(watched, name).write_bytes(secrets.token_bytes(8))
                created.append(name)
            stdout, stderr = proc.communicate(timeout=3)
        except Exception:
            proc.kill()
            proc.communicate()
            raise

        assert proc.returncode == 0, f"inotifywait failed to watch a directory: {stderr}"
        assert any((":" + name) in stdout for name in created), f"inotifywait did not report a created file: {stdout!r}"


def record(name, path, digest, description):
    return (
        f"[Artifact: {name}]\n"
        f"Path: {path}\n"
        f"Hash: {digest}\n"
        f"Description: {description}\n\n"
    )


def encoded(text, encoding):
    if encoding == "utf16le":
        return text.encode("utf-16le")
    if encoding == "utf16bom":
        return text.encode("utf-16")
    if encoding == "cp1252":
        return text.encode("cp1252")
    raise AssertionError(encoding)


def test_generated_clean_manifests_are_converted_exactly():
    token = secrets.token_hex(7)
    digest1 = secrets.token_hex(32)
    digest2 = secrets.token_hex(32)
    digest3 = secrets.token_hex(32)

    clean_cases = [
        (
            record("App_" + token, "bin/" + token + "/app", digest1,
                   "First description line\ncontinued description " + token),
            "utf16le",
        ),
        (
            record("Tool-" + token, "lib/" + token + "/libtool.so", digest2,
                   "BOM encoded manifest " + token),
            "utf16bom",
        ),
        (
            record("Data_" + token, "share/" + token + "/data.bin", digest3,
                   "Windows text: café costs €5 and uses “quotes” " + token),
            "cp1252",
        ),
        (
            record("One_" + token, "pkg/one.bin", digest1, "Record one " + token)
            + record("Two-" + token, "pkg/sub/two.bin", digest2, "Record two " + token),
            "cp1252",
        ),
    ]

    with tempfile.TemporaryDirectory(prefix="incoming-" + secrets.token_hex(8) + "-") as td:
        for index, (text, encoding) in enumerate(clean_cases):
            path = Path(td, secrets.token_hex(10) + f"-{index}.manifest")
            path.write_bytes(encoded(text, encoding))
            result = subprocess.run([SCRIPT, str(path)], capture_output=True)
            assert result.returncode == 0, f"valid {encoding} manifest was rejected: {result.stderr!r}"
            assert result.stdout == text.encode("utf-8"), "sanitizer output did not exactly match the UTF-8 converted manifest"


def test_generated_invalid_manifests_are_rejected_silently():
    token = secrets.token_hex(7)
    good_hash = secrets.token_hex(32)
    base_name = "Good_" + token
    base_path = "bin/" + token + "/app"

    invalid_texts = [
        record(base_name, "/opt/" + token + "/app", good_hash, "absolute path"),
        record(base_name, "lib/../secret/" + token, good_hash, "path traversal"),
        record("Bad$" + token, base_path, good_hash, "dollar injection"),
        record("Bad;" + token, base_path, good_hash, "semicolon injection"),
        record("Bad|" + token, base_path, good_hash, "pipe injection"),
        record(base_name, base_path, good_hash[:-1], "short hash"),
        record(base_name, base_path, good_hash[:-1] + "g", "non-hex hash"),
        record(base_name, base_path, good_hash.upper(), "uppercase hash"),
        f"[Artifact: {base_name}]\nHash: {good_hash}\nDescription: missing path\n\n",
        f"[Artifact: {base_name}]\nPath: {base_path}\nDescription: missing hash\n\n",
        record("GoodFirst_" + token, "safe/first.bin", good_hash, "valid first record")
        + record("Bad<" + token, "safe/second.bin", good_hash, "invalid later record"),
    ]
    encodings = ["utf16le", "cp1252", "utf16bom"]

    with tempfile.TemporaryDirectory(prefix="pending-" + secrets.token_hex(8) + "-") as td:
        for index, text in enumerate(invalid_texts):
            encoding = encodings[index % len(encodings)]
            path = Path(td, secrets.token_hex(10) + f"-{index}.manifest")
            path.write_bytes(encoded(text, encoding))
            result = subprocess.run([SCRIPT, str(path)], capture_output=True)
            assert result.returncode != 0, f"invalid {encoding} manifest was accepted"
            assert result.stdout == b"", "invalid manifest produced stdout"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
