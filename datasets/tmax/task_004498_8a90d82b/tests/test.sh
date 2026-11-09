#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import struct
import subprocess
import configparser
import pytest
import urllib.request
import urllib.error

FILTER_BIN = "/home/user/archive_filter"
CLEAN_CORPUS_DIR = "/home/user/corpus/clean/"
EVIL_CORPUS_DIR = "/home/user/corpus/evil/"
CONFIG_PATH = "/app/flask_app/config.ini"
MAX_CHUNK = 1048576


def run_filter(path):
    try:
        return subprocess.run(
            [FILTER_BIN, os.path.abspath(path)],
            capture_output=True,
            timeout=5,
        ).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"Filter timed out while parsing {path}")


def make_archive(chunks):
    data = bytearray(b"CHNK" + struct.pack("<I", len(chunks)))
    for chunk in chunks:
        data += struct.pack("<I", len(chunk))
        data += chunk
    return bytes(data)


def test_filter_binary_exists_and_executable():
    assert os.path.isfile(FILTER_BIN), f"Filter binary {FILTER_BIN} does not exist."
    assert os.access(FILTER_BIN, os.X_OK), f"Filter binary {FILTER_BIN} is not executable."
    with open(FILTER_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "archive_filter must be a compiled executable binary."


def test_filter_clean_corpus():
    if not os.path.isdir(CLEAN_CORPUS_DIR):
        pytest.skip("Clean corpus directory not found.")

    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    failed_files = []

    for f in clean_files:
        filepath = os.path.join(CLEAN_CORPUS_DIR, f)
        result = subprocess.run([FILTER_BIN, filepath], capture_output=True)
        if result.returncode != 0:
            failed_files.append(f)

    assert len(failed_files) == 0, f"{len(failed_files)} of {len(clean_files)} clean files rejected (expected exit 0). Offending files: {failed_files}"


def test_filter_evil_corpus():
    if not os.path.isdir(EVIL_CORPUS_DIR):
        pytest.skip("Evil corpus directory not found.")

    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    failed_files = []

    for f in evil_files:
        filepath = os.path.join(EVIL_CORPUS_DIR, f)
        result = subprocess.run([FILTER_BIN, filepath], capture_output=True)
        if result.returncode != 1:
            failed_files.append(f)

    assert len(failed_files) == 0, f"{len(failed_files)} of {len(evil_files)} evil files bypassed (expected exit 1). Offending files: {failed_files}"


def test_generated_adversarial_archives(tmp_path):
    random_chunks = [os.urandom(int.from_bytes(os.urandom(2), "little") % 4097) for _ in range(7)]
    clean_cases = [
        make_archive([]),
        make_archive([b""]),
        make_archive(random_chunks),
        make_archive([b"Z" * MAX_CHUNK]),
        make_archive([os.urandom(31), b"", os.urandom(257)]),
    ]

    valid_for_mutation = make_archive([os.urandom(53), os.urandom(127)])
    evil_cases = [
        b"",
        b"CHN",
        b"BADD" + struct.pack("<I", 0),
        b"CHNK" + b"\x01\x00\x00",
        b"CHNK" + struct.pack("<I", 1),
        b"CHNK" + struct.pack("<I", 1) + struct.pack("<I", 20) + os.urandom(19),
        b"CHNK" + struct.pack("<I", 1) + struct.pack("<I", MAX_CHUNK + 1),
        make_archive([]) + os.urandom(1),
        valid_for_mutation[:-1],
        valid_for_mutation + os.urandom(3),
        b"CHNK" + struct.pack("<I", 2) + struct.pack("<I", 0),
        b"CHNK" + struct.pack("<I", 0xffffffff),
    ]

    for i, contents in enumerate(clean_cases):
        path = tmp_path / f"clean-{i}-{os.urandom(8).hex()}.chnk"
        path.write_bytes(contents)
        assert run_filter(str(path)) == 0, f"Generated valid archive {i} was rejected"

    for i, contents in enumerate(evil_cases):
        path = tmp_path / f"evil-{i}-{os.urandom(8).hex()}.chnk"
        path.write_bytes(contents)
        assert run_filter(str(path)) == 1, f"Generated invalid archive {i} was accepted"


def test_config_updated():
    assert os.path.isfile(CONFIG_PATH), f"Config file {CONFIG_PATH} does not exist."
    config = configparser.ConfigParser()
    config.read(CONFIG_PATH)
    assert 'Upload' in config, "[Upload] section missing in config.ini"
    assert 'FILTER_CMD' in config['Upload'], "FILTER_CMD missing in config.ini"
    assert config['Upload']['FILTER_CMD'] == FILTER_BIN, f"FILTER_CMD is not set to {FILTER_BIN}."


def test_end_to_end_pipeline():
    # Only test if corpus files are available
    if not os.path.isdir(CLEAN_CORPUS_DIR) or not os.path.isdir(EVIL_CORPUS_DIR):
        pytest.skip("Corpus directories not found, skipping end-to-end test.")

    clean_files = os.listdir(CLEAN_CORPUS_DIR)
    evil_files = os.listdir(EVIL_CORPUS_DIR)

    if clean_files:
        clean_path = os.path.join(CLEAN_CORPUS_DIR, clean_files[0])
        with open(clean_path, 'rb') as f:
            data = f.read()
        req = urllib.request.Request("http://localhost:8080/upload", data=data, method="POST")
        try:
            with urllib.request.urlopen(req) as response:
                assert response.status == 200, f"Clean upload returned status {response.status}, expected 200."
        except urllib.error.HTTPError as e:
            pytest.fail(f"Clean upload failed with HTTP error: {e.code}")

    if evil_files:
        evil_path = os.path.join(EVIL_CORPUS_DIR, evil_files[0])
        with open(evil_path, 'rb') as f:
            data = f.read()
        req = urllib.request.Request("http://localhost:8080/upload", data=data, method="POST")
        try:
            with urllib.request.urlopen(req) as response:
                pytest.fail(f"Evil upload succeeded with status {response.status}, expected 400.")
        except urllib.error.HTTPError as e:
            assert e.code == 400, f"Evil upload returned status {e.code}, expected 400."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
