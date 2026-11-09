#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import posixpath
import random
import secrets
import struct
import subprocess
import tempfile

import pytest

SCRIPT_PATH = "/home/user/filter_archive.py"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"


def run_filter(filepath):
    return subprocess.run(
        ["python3", SCRIPT_PATH, filepath],
        capture_output=True,
        timeout=5,
    )


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."


def test_clean_corpus():
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*"))
    assert len(clean_files) > 0, "No clean corpus files found."

    rejected = []
    for filepath in clean_files:
        result = run_filter(filepath)
        if result.returncode != 0:
            rejected.append(os.path.basename(filepath))

    if rejected:
        pytest.fail(f"{len(rejected)} of {len(clean_files)} clean rejected: {', '.join(rejected)}")


def test_evil_corpus():
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*"))
    assert len(evil_files) > 0, "No evil corpus files found."

    bypassed = []
    for filepath in evil_files:
        result = run_filter(filepath)
        if result.returncode == 0:
            bypassed.append(os.path.basename(filepath))

    if bypassed:
        pytest.fail(f"{len(bypassed)} of {len(evil_files)} evil bypassed: {', '.join(bypassed)}")


def make_entry(path, entry_type, data):
    path_bytes = path if isinstance(path, bytes) else path.encode("utf-8")
    data_bytes = data if isinstance(data, bytes) else data.encode("utf-8")
    return (
        struct.pack("<H", len(path_bytes))
        + path_bytes
        + bytes([entry_type])
        + struct.pack("<I", len(data_bytes))
        + data_bytes
    )


def expected_safe(blob):
    if len(blob) < 4 or blob[:4] != b"ARTF":
        return False

    offset = 4
    while offset < len(blob):
        if len(blob) - offset < 2:
            return False
        path_length = struct.unpack_from("<H", blob, offset)[0]
        offset += 2

        if len(blob) - offset < path_length:
            return False
        path_bytes = blob[offset:offset + path_length]
        offset += path_length
        try:
            path = path_bytes.decode("utf-8")
        except UnicodeDecodeError:
            return False

        if len(blob) - offset < 5:
            return False
        entry_type = blob[offset]
        offset += 1
        if entry_type not in (0, 1):
            return False

        data_length = struct.unpack_from("<I", blob, offset)[0]
        offset += 4
        if len(blob) - offset < data_length:
            return False
        data = blob[offset:offset + data_length]
        offset += data_length

        if path.startswith("/") or "../" in path:
            return False

        if entry_type == 1:
            try:
                target = data.decode("utf-8")
            except UnicodeDecodeError:
                return False
            if target.startswith("/") or "../" in target:
                return False
            link_name = posixpath.basename(path)
            if link_name and link_name in target:
                return False
            if "." in target.split("/"):
                return False

    return True


def token():
    return secrets.token_hex(8)


def test_generated_archives_with_derived_expectations():
    archives = []

    # Randomized valid archives, including empty archives, files, and safe symlinks.
    for _ in range(24):
        entries = []
        for index in range(secrets.randbelow(5)):
            stem = token()
            if index % 3 == 2:
                path = f"links/shortcut_{stem}"
                target = f"objects/item_{token()}.dat"
                entries.append(make_entry(path, 1, target))
            else:
                path = f"pkg_{stem}/data_{token()}.bin"
                entries.append(make_entry(path, 0, os.urandom(secrets.randbelow(40))))
        archives.append(b"ARTF" + b"".join(entries))

    # Randomized violations of each path and symlink rule.
    for _ in range(8):
        name = "loop_" + token()
        archives.extend([
            b"ARTF" + make_entry(f"/{token()}/file", 0, os.urandom(4)),
            b"ARTF" + make_entry(f"dir_{token()}/../escape", 0, b"x"),
            b"ARTF" + make_entry(f"links/{token()}", 1, f"/{token()}/target"),
            b"ARTF" + make_entry(f"links/{token()}", 1, f"safe/../{token()}"),
            b"ARTF" + make_entry(f"links/{name}", 1, f"other/{name}/child"),
            b"ARTF" + make_entry(f"links/{token()}", 1, f"dir_{token()}/./child"),
            b"ARTF" + make_entry(f"links/{token()}", 1, "."),
        ])

    # Malformed headers, invalid UTF-8/type fields, and varied truncation points.
    archives.extend([b"", b"A", b"ART", b"ARTX", b"ARTF\x01"])
    archives.append(b"ARTF" + make_entry(b"bad\xffpath", 0, b"x"))
    archives.append(b"ARTF" + make_entry("ordinary/path", 2, b"x"))
    archives.append(b"ARTF" + make_entry("links/ordinary", 1, b"bad\xfftarget"))

    complete = b"ARTF" + make_entry(f"dir_{token()}/file_{token()}", 0, os.urandom(19))
    for cut in range(5, len(complete)):
        archives.append(complete[:cut])

    first = make_entry(f"first_{token()}", 0, b"complete")
    second = make_entry(f"second_{token()}", 0, os.urandom(13))
    combined = b"ARTF" + first + second
    second_start = 4 + len(first)
    for cut in range(second_start + 1, len(combined)):
        archives.append(combined[:cut])

    random.SystemRandom().shuffle(archives)
    assert any(expected_safe(blob) for blob in archives)
    assert any(not expected_safe(blob) for blob in archives)

    failures = []
    with tempfile.TemporaryDirectory(prefix="artf_checks_") as directory:
        for blob in archives:
            # Names are random and do not disclose the expected classification.
            filepath = os.path.join(directory, secrets.token_hex(16) + ".bin")
            with open(filepath, "wb") as archive_file:
                archive_file.write(blob)

            expected_code = 0 if expected_safe(blob) else 1
            result = run_filter(filepath)
            if result.returncode != expected_code:
                failures.append(
                    f"{os.path.basename(filepath)} expected {expected_code}, got {result.returncode}"
                )

    if failures:
        pytest.fail(f"{len(failures)} generated cases failed; " + "; ".join(failures[:10]))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
