#!/bin/bash
mkdir -p /logs/verifier
status=0

if [ ! -f /home/user/curate.py ]; then
    echo "Missing required Python script: /home/user/curate.py" >&2
    status=1
fi

if [ "$status" -eq 0 ]; then
python3 - <<'PY' || status=1
import io
import os
import secrets
import tarfile

raw_root = "/home/user/artifacts_raw"
token = secrets.token_hex(12)
artifact_id = "verify_" + token
payload_name = "payload_" + secrets.token_hex(6) + ".blob"
payload = secrets.token_bytes(47) + b"\x00\xff\x10"
archive_dir = os.path.join(raw_root, "verifier_challenge_" + token, "deep", "more")
os.makedirs(archive_dir, exist_ok=True)
archive_path = os.path.join(archive_dir, "challenge_" + token + ".tar.gz")
meta = (f"[Artifact]\nid={artifact_id}\npayload_file={payload_name}\n").encode("utf-8")

with tarfile.open(archive_path, "w:gz") as tf:
    meta_info = tarfile.TarInfo("meta.ini")
    meta_info.size = len(meta)
    tf.addfile(meta_info, io.BytesIO(meta))

    payload_info = tarfile.TarInfo(payload_name)
    payload_info.size = len(payload)
    tf.addfile(payload_info, io.BytesIO(payload))
PY
fi

if [ "$status" -eq 0 ]; then
    timeout 30s python3 /home/user/curate.py || status=1
fi

cat <<'TEST_EOF' > /tmp/test_final_state.py
import configparser
import glob
import json
import os
import tarfile
import pytest

TARGET_DIR = "/home/user/artifacts_curated"
RAW_DIR = "/home/user/artifacts_raw"

EXPECTED_JSON = {
    "art_001.json": {"id": "art_001", "payload_file": "data1.bin"},
    "omega_42.json": {"id": "omega_42", "payload_file": "payload.dat"},
    "zeta_77.json": {"id": "zeta_77", "payload_file": "core.dump"}
}

EXPECTED_BIN = {
    "art_001.bin": b"CURATED_\x01\x02\x03\x04\x0A\x0B\x0C",
    "omega_42.bin": b"CURATED_\xFF\xEE\xDD\xCC\xBB\xAA",
    "zeta_77.bin": b"CURATED_\x00\x00\x00\x00\x42\x42"
}

def test_script_exists():
    assert os.path.isfile("/home/user/curate.py"), "Required script /home/user/curate.py is missing."

def test_target_directory_exists():
    assert os.path.isdir(TARGET_DIR), f"Target directory {TARGET_DIR} does not exist. Did you run the script?"

@pytest.mark.parametrize("fname, expected_data", EXPECTED_JSON.items())
def test_json_files(fname, expected_data):
    file_path = os.path.join(TARGET_DIR, fname)
    assert os.path.isfile(file_path), f"Expected JSON file {file_path} is missing."

    with open(file_path, 'r', encoding='utf-8') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {file_path} does not contain valid JSON.")

    assert data == expected_data, f"Data in {file_path} does not match expected output."

@pytest.mark.parametrize("fname, expected_data", EXPECTED_BIN.items())
def test_binary_files(fname, expected_data):
    file_path = os.path.join(TARGET_DIR, fname)
    assert os.path.isfile(file_path), f"Expected binary file {file_path} is missing."

    with open(file_path, 'rb') as f:
        data = f.read()

    assert data.startswith(b"CURATED_"), f"Binary file {file_path} does not start with 'CURATED_'."
    assert data == expected_data, f"Binary data in {file_path} does not match the expected modified payload."

def test_random_recursive_archive_was_processed():
    archives = glob.glob(os.path.join(RAW_DIR, "verifier_challenge_*", "deep", "more", "*.tar.gz"))
    assert archives, "Verifier challenge archive was not created."

    for archive_path in archives:
        with tarfile.open(archive_path, "r:gz") as tf:
            meta_member = tf.getmember("meta.ini")
            with tf.extractfile(meta_member) as meta_file:
                assert meta_file is not None
                parser = configparser.ConfigParser()
                parser.read_string(meta_file.read().decode("utf-8"))

            artifact_id = parser["Artifact"]["id"]
            payload_name = parser["Artifact"]["payload_file"]
            payload_member = tf.getmember(payload_name)
            with tf.extractfile(payload_member) as payload_file:
                assert payload_file is not None
                expected_payload = payload_file.read()

        json_path = os.path.join(TARGET_DIR, artifact_id + ".json")
        bin_path = os.path.join(TARGET_DIR, artifact_id + ".bin")
        assert os.path.isfile(json_path), f"Dynamic JSON output {json_path} is missing."
        assert os.path.isfile(bin_path), f"Dynamic binary output {bin_path} is missing."

        with open(json_path, "r", encoding="utf-8") as f:
            assert json.load(f) == {"id": artifact_id, "payload_file": payload_name}
        with open(bin_path, "rb") as f:
            assert f.read() == b"CURATED_" + expected_payload
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 || status=1

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
