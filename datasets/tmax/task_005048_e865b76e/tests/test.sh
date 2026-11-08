#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import stat
import subprocess
import uuid

import pytest

EVIL_DIR = "/app/data/evil"
CLEAN_DIR = "/app/data/clean"
FTP_DIR = "/app/ftp_root/data"
PROCESSED_DIR = "/home/user/processed"
PIPELINE_SCRIPT = "/home/user/filter_pipeline.py"
WEBHOOK_LOG = "/app/webhook.log"

DYNAMIC_CASES = {}


def get_redis_results():
    """Fetch the contents of the pipeline:results list from Redis."""
    try:
        out = subprocess.check_output(
            ['redis-cli', 'LRANGE', 'pipeline:results', '0', '-1'],
            text=True
        )
        results = []
        for line in out.strip().split('\n'):
            if line.strip():
                try:
                    results.append(json.loads(line.strip()))
                except json.JSONDecodeError:
                    pass
        return results
    except Exception:
        return []


def decode_fixture_bytes(data):
    if data.startswith(b'\xef\xbb\xbf'):
        return data.decode('utf-8-sig')
    if data.startswith((b'\xff\xfe', b'\xfe\xff')):
        return data.decode('utf-16')

    even_nuls = sum(b == 0 for b in data[0::2])
    odd_nuls = sum(b == 0 for b in data[1::2])
    if len(data) >= 4 and odd_nuls > max(1, len(data[1::2]) // 4):
        return data.decode('utf-16le')
    if len(data) >= 4 and even_nuls > max(1, len(data[0::2]) // 4):
        return data.decode('utf-16be')

    for encoding in ('utf-8', 'shift_jis', 'cp1252'):
        try:
            return data.decode(encoding)
        except UnicodeDecodeError:
            pass
    raise AssertionError('Unable to decode verifier fixture')


@pytest.fixture(scope='session', autouse=True)
def execute_pipeline_against_fresh_inputs():
    st = os.lstat(PIPELINE_SCRIPT)
    assert stat.S_ISREG(st.st_mode), f"{PIPELINE_SCRIPT} must be a regular file"

    os.makedirs(FTP_DIR, exist_ok=True)
    os.makedirs(PROCESSED_DIR, exist_ok=True)

    token = uuid.uuid4().hex
    cases = {
        f"verify_utf8_{token}.txt": (f"fresh UTF-8 clean data {token}", 'utf-8', 'ACCEPTED'),
        f"verify_cp1252_{token}.txt": (f"Résumé £ clean {token}", 'cp1252', 'ACCEPTED'),
        f"verify_sjis_{token}.txt": (f"安全なデータ {token}", 'shift_jis', 'ACCEPTED'),
        f"verify_script_{token}.txt": (f"prefix <ScRiPt>alert('{token}')</script>", 'utf-16le', 'REJECTED'),
        f"verify_union_{token}.txt": (f"café UNION SELECT secret_{token}", 'cp1252', 'REJECTED'),
    }

    for filename, (text, encoding, status) in cases.items():
        with open(os.path.join(FTP_DIR, filename), 'wb') as f:
            f.write(text.encode(encoding))
        DYNAMIC_CASES[filename] = {'text': text, 'status': status}

    for entry in os.listdir(PROCESSED_DIR):
        path = os.path.join(PROCESSED_DIR, entry)
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)

    subprocess.run(['redis-cli', 'DEL', 'pipeline:results'], check=True,
                   stdout=subprocess.DEVNULL)
    with open(WEBHOOK_LOG, 'w', encoding='utf-8'):
        pass

    completed = subprocess.run(
        ['python3', PIPELINE_SCRIPT],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert completed.returncode == 0, (
        f"Pipeline exited with {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )


def test_adversarial_corpus_results():
    evil_files = set(os.listdir(EVIL_DIR)) if os.path.exists(EVIL_DIR) else set()
    clean_files = set(os.listdir(CLEAN_DIR)) if os.path.exists(CLEAN_DIR) else set()

    processed_files = set(os.listdir(PROCESSED_DIR)) if os.path.exists(PROCESSED_DIR) else set()

    redis_results = get_redis_results()
    redis_status_map = {}
    for item in redis_results:
        if 'filename' in item and 'status' in item:
            redis_status_map[item['filename']] = item['status']

    evil_bypassed = []
    for ef in evil_files:
        if ef in processed_files:
            evil_bypassed.append(ef)
        elif redis_status_map.get(ef) != "REJECTED":
            evil_bypassed.append(f"{ef} (not marked REJECTED in Redis)")

    clean_modified_or_rejected = []
    for cf in clean_files:
        if cf not in processed_files:
            clean_modified_or_rejected.append(f"{cf} (missing from processed)")
        elif redis_status_map.get(cf) != "ACCEPTED":
            clean_modified_or_rejected.append(f"{cf} (not marked ACCEPTED in Redis)")

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified_or_rejected:
        errors.append(f"{len(clean_modified_or_rejected)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_modified_or_rejected)}")

    assert not errors, " | ".join(errors)


def test_clean_files_utf8():
    clean_files = os.listdir(CLEAN_DIR) if os.path.exists(CLEAN_DIR) else []
    for cf in clean_files:
        processed_path = os.path.join(PROCESSED_DIR, cf)
        if os.path.exists(processed_path):
            try:
                with open(processed_path, 'r', encoding='utf-8') as f:
                    f.read()
            except UnicodeDecodeError:
                pytest.fail(f"Clean file {cf} was not saved as valid UTF-8 in {PROCESSED_DIR}")


def test_webhook_log_contains_clean_data():
    assert os.path.exists(WEBHOOK_LOG), f"Webhook log not found at {WEBHOOK_LOG}"

    with open(WEBHOOK_LOG, 'r', encoding='utf-8', errors='replace') as f:
        log_content = f.read()

    assert len(log_content) > 0, "Webhook log is empty, meaning no data was forwarded to the webhook endpoint."


def test_fresh_dynamic_files_have_correct_results_and_contents():
    redis_results = get_redis_results()

    for filename, expected in DYNAMIC_CASES.items():
        matching = [item for item in redis_results
                    if isinstance(item, dict) and item.get('filename') == filename]
        assert len(matching) == 1, f"Expected exactly one Redis result for {filename}, got {matching}"
        assert matching[0].get('status') == expected['status']

        processed_path = os.path.join(PROCESSED_DIR, filename)
        if expected['status'] == 'ACCEPTED':
            assert os.path.isfile(processed_path), f"Accepted file {filename} was not saved"
            with open(processed_path, 'rb') as f:
                output = f.read()
            assert output == expected['text'].encode('utf-8'), (
                f"Processed content for {filename} does not equal the decoded FTP input"
            )
        else:
            assert not os.path.exists(processed_path), f"Rejected file {filename} was saved"


def test_original_clean_outputs_equal_decoded_ftp_inputs():
    for filename in os.listdir(CLEAN_DIR):
        ftp_path = os.path.join(FTP_DIR, filename)
        assert os.path.isfile(ftp_path), f"Clean FTP input {filename} is missing"
        with open(ftp_path, 'rb') as f:
            expected_text = decode_fixture_bytes(f.read())
        with open(os.path.join(PROCESSED_DIR, filename), 'rb') as f:
            actual = f.read()
        assert actual == expected_text.encode('utf-8'), (
            f"Processed content for {filename} does not equal the decoded FTP input"
        )


def test_webhook_received_each_clean_body_and_no_rejected_payload():
    with open(WEBHOOK_LOG, 'r', encoding='utf-8', errors='strict') as f:
        log_content = f.read()

    for filename, expected in DYNAMIC_CASES.items():
        if expected['status'] == 'ACCEPTED':
            assert expected['text'] in log_content, f"Webhook did not receive clean body for {filename}"
        else:
            assert expected['text'] not in log_content, f"Webhook received rejected body for {filename}"

    for filename in os.listdir(CLEAN_DIR):
        with open(os.path.join(FTP_DIR, filename), 'rb') as f:
            expected_text = decode_fixture_bytes(f.read())
        assert expected_text in log_content, f"Webhook did not receive clean body for {filename}"

    lowered = log_content.casefold()
    assert '<script' not in lowered
    assert 'drop table' not in lowered
    assert 'union select' not in lowered
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
