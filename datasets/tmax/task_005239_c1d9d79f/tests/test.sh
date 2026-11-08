#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import re
import secrets
import subprocess
import tarfile

EXECUTABLE = "/home/user/dataset_filter"
SOURCE = "/home/user/dataset_filter.c"
CONFIG = "/home/user/filter.conf"
EVIL_DIR = "/app/datasets/evil/"
CLEAN_DIR = "/app/datasets/clean/"


def run_filter(data):
    return subprocess.run(
        [EXECUTABLE], input=data, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=10
    ).returncode


def make_tar(entries):
    """entries is a sequence of (archive_name, payload_bytes)."""
    out = io.BytesIO()
    with tarfile.open(fileobj=out, mode="w", format=tarfile.USTAR_FORMAT) as archive:
        for name, payload in entries:
            info = tarfile.TarInfo(name)
            info.size = len(payload)
            info.mode = 0o600
            archive.addfile(info, io.BytesIO(payload))
    return out.getvalue()


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Executable not found at {EXECUTABLE}"
    assert os.access(EXECUTABLE, os.X_OK), f"File at {EXECUTABLE} is not executable"
    with open(EXECUTABLE, "rb") as executable:
        assert executable.read(4) == b"\x7fELF", "dataset_filter must be a compiled executable"


def test_c_source_and_libtar_linkage():
    assert os.path.isfile(SOURCE), f"C source not found at {SOURCE}"
    source = open(SOURCE, "r", encoding="utf-8", errors="replace").read()
    assert re.search(r"#\s*include\s*[<\"](?:[^>\"]*/)?libtar\.h[>\"]", source), \
        "dataset_filter.c does not include libtar.h"
    assert re.search(r"\b(?:tar_open|tar_fdopen|th_read|tar_skip_regfile)\s*\(", source), \
        "dataset_filter.c does not appear to use the libtar API"

    dynamic = subprocess.run(
        ["readelf", "-d", EXECUTABLE], capture_output=True, text=True
    ).stdout
    symbols = subprocess.run(
        ["nm", "-a", EXECUTABLE], capture_output=True, text=True
    ).stdout
    evidence = dynamic + "\n" + symbols
    assert re.search(r"libtar|\b(?:tar_open|tar_fdopen|th_read|tar_skip_regfile)\b", evidence), \
        "compiled executable has no evidence of being linked with libtar"


def test_adversarial_corpus():
    assert os.path.isdir(EVIL_DIR), f"Evil corpus directory missing: {EVIL_DIR}"
    assert os.path.isdir(CLEAN_DIR), f"Clean corpus directory missing: {CLEAN_DIR}"

    evil_files = [os.path.join(EVIL_DIR, f) for f in os.listdir(EVIL_DIR) if f.endswith('.tar')]
    clean_files = [os.path.join(CLEAN_DIR, f) for f in os.listdir(CLEAN_DIR) if f.endswith('.tar')]

    assert len(evil_files) > 0, "No evil corpus files found."
    assert len(clean_files) > 0, "No clean corpus files found."

    evil_bypassed = []
    clean_modified = []

    for evil_file in evil_files:
        with open(evil_file, 'rb') as f:
            result = subprocess.run([EXECUTABLE], stdin=f, capture_output=True)
            if result.returncode != 1:
                evil_bypassed.append(os.path.basename(evil_file))

    for clean_file in clean_files:
        with open(clean_file, 'rb') as f:
            result = subprocess.run([EXECUTABLE], stdin=f, capture_output=True)
            if result.returncode != 0:
                clean_modified.append(os.path.basename(clean_file))

    error_msg = []
    if evil_bypassed:
        error_msg.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_msg.append(f"{len(clean_modified)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_modified)}")

    assert not error_msg, " | ".join(error_msg)


def test_generated_archives_and_runtime_configuration():
    token = secrets.token_hex(12)
    prefix = f"generated_{token}_"
    original_config = open(CONFIG, "rb").read()

    try:
        with open(CONFIG, "w", encoding="utf-8") as config:
            config.write(f"ALLOWED_PREFIX={prefix}\nMAX_FILES=3\n")

        clean = make_tar([
            (prefix + "alpha.bin", secrets.token_bytes(31)),
            (prefix + "beta.bin", secrets.token_bytes(777)),
            (prefix + "gamma.bin", b""),
        ])
        assert run_filter(clean) == 0, "generated safe archive was rejected"

        wrong_prefix = make_tar([("not_allowed_" + token, b"x")])
        assert run_filter(wrong_prefix) == 1, "archive with a generated wrong prefix was accepted"

        absolute = make_tar([("/tmp/" + prefix + "absolute.bin", b"x")])
        assert run_filter(absolute) == 1, "archive containing an absolute path was accepted"

        traversal = make_tar([("safe/../" + prefix + "escape.bin", b"x")])
        assert run_filter(traversal) == 1, "archive containing path traversal was accepted"

        too_many = make_tar([
            (prefix + f"item_{i}.bin", secrets.token_bytes(i + 1)) for i in range(4)
        ])
        assert run_filter(too_many) == 1, "archive exceeding generated MAX_FILES was accepted"

        valid_for_corruption = bytearray(make_tar([(prefix + "checksum.bin", b"payload")]))
        valid_for_corruption[0] ^= 1
        assert run_filter(bytes(valid_for_corruption)) == 1, "archive with a bad header checksum was accepted"

        payload = secrets.token_bytes(32768)
        complete = make_tar([(prefix + "truncated.bin", payload)])
        truncated = complete[:512 + len(payload) // 2]
        assert run_filter(truncated) == 1, "archive truncated inside file data was accepted"
    finally:
        with open(CONFIG, "wb") as config:
            config.write(original_config)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
