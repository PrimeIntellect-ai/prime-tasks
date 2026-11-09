#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import binascii
import json
import os
import random
import secrets
import struct
import subprocess
import tempfile


def run_checked(cmd, timeout=15):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)


def test_video_event_result():
    path = "/home/user/video_event.txt"
    assert os.path.isfile(path), f"Missing required file: {path}"
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "142-187", f"Incorrect frame range in {path}. Expected '142-187', got '{content}'"


def test_sanitizer_adversarial_corpus():
    sanitizer_src = "/home/user/sanitizer.go"
    assert os.path.isfile(sanitizer_src), f"Missing required file: {sanitizer_src}"

    sanitizer_bin = "/tmp/sanitizer"
    compile_res = run_checked(["go", "build", "-o", sanitizer_bin, sanitizer_src])
    assert compile_res.returncode == 0, f"Failed to compile {sanitizer_src}:\n{compile_res.stderr}"
    assert os.path.isfile(sanitizer_bin), f"Sanitizer binary not generated at {sanitizer_bin}"

    evil_corpus_dir = "/app/eval_corpus/evil"
    clean_corpus_dir = "/app/eval_corpus/clean"
    if not os.path.isdir(evil_corpus_dir):
        evil_corpus_dir = "/app/corpus/evil"
    if not os.path.isdir(clean_corpus_dir):
        clean_corpus_dir = "/app/corpus/clean"

    assert os.path.isdir(evil_corpus_dir), f"Missing evil corpus directory: {evil_corpus_dir}"
    assert os.path.isdir(clean_corpus_dir), f"Missing clean corpus directory: {clean_corpus_dir}"

    evil_bypassed = []
    clean_modified = []
    for filename in os.listdir(evil_corpus_dir):
        filepath = os.path.join(evil_corpus_dir, filename)
        if os.path.isfile(filepath):
            res = subprocess.run([sanitizer_bin, filepath], timeout=10)
            if res.returncode != 1:
                evil_bypassed.append(filename)

    for filename in os.listdir(clean_corpus_dir):
        filepath = os.path.join(clean_corpus_dir, filename)
        if os.path.isfile(filepath):
            res = subprocess.run([sanitizer_bin, filepath], timeout=10)
            if res.returncode != 0:
                clean_modified.append(filename)

    error_messages = []
    if evil_bypassed:
        error_messages.append(f"{len(evil_bypassed)} of {len(os.listdir(evil_corpus_dir))} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_messages.append(f"{len(clean_modified)} of {len(os.listdir(clean_corpus_dir))} clean modified/rejected: {', '.join(clean_modified)}")
    assert not error_messages, " | ".join(error_messages)

    # Exercise the inferred token-length vulnerability on unpublished, randomly
    # named inputs. Padding makes total file size an unreliable classifier.
    cases = []
    nonce = secrets.token_hex(12)
    for length in (0, 1, 100, 511, 512):
        cases.append((0, {
            "request": nonce,
            "auth_token": "c" * length,
            "padding": secrets.token_hex(random.randint(260, 520)),
        }))
    for length in (513, 514, 600, 777):
        cases.append((1, {
            "padding": secrets.token_hex(random.randint(0, 80)),
            "auth_token": "e" * length,
            "request": nonce,
        }))
    random.SystemRandom().shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="payload_checks_") as td:
        for index, (expected, payload) in enumerate(cases):
            path = os.path.join(td, secrets.token_hex(10))
            with open(path, "w") as f:
                if index % 2:
                    json.dump(payload, f, indent=2)
                else:
                    json.dump(payload, f, separators=(",", ":"))
            res = subprocess.run([sanitizer_bin, path], timeout=10)
            assert res.returncode == expected, (
                f"Sanitizer returned {res.returncode} for an auth_token of length "
                f"{len(payload['auth_token'])}; expected {expected}"
            )


def wal_record(payload_bytes, checksum=None):
    if checksum is None:
        checksum = binascii.crc32(payload_bytes) & 0xffffffff
    return b"WAL1" + struct.pack("<I", len(payload_bytes)) + payload_bytes + struct.pack("<I", checksum)


def expected_wal_payloads(data):
    result = []
    pos = 0
    while True:
        start = data.find(b"WAL1", pos)
        if start < 0:
            break
        if start + 8 > len(data):
            break
        length = struct.unpack_from("<I", data, start + 4)[0]
        payload_start = start + 8
        payload_end = payload_start + length
        checksum_end = payload_end + 4
        if checksum_end <= len(data):
            payload = data[payload_start:payload_end]
            stored = struct.unpack_from("<I", data, payload_end)[0]
            if (binascii.crc32(payload) & 0xffffffff) == stored:
                try:
                    result.append(json.loads(payload.decode("utf-8")))
                    pos = checksum_end
                    continue
                except (UnicodeDecodeError, json.JSONDecodeError):
                    pass
        pos = start + 1
    return result


def read_recovered(path):
    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    parsed = []
    for line in lines:
        parsed.append(json.loads(line))
    return parsed


def execute_recovery(binary, expected):
    output = "/home/user/recovered.jsonl"
    if os.path.exists(output):
        os.remove(output)
    res = run_checked([binary])
    assert res.returncode == 0, f"Recovery program failed:\nstdout: {res.stdout}\nstderr: {res.stderr}"
    assert os.path.isfile(output), f"Recovery program did not create {output}"
    actual = read_recovered(output)
    assert actual == expected, f"Recovered records differ. Expected {expected!r}, got {actual!r}"


def test_recovery_program_executes_and_recovers_records():
    recover_src = "/home/user/recover.go"
    recovered_jsonl = "/home/user/recovered.jsonl"
    assert os.path.isfile(recover_src), f"Missing required file: {recover_src}"
    assert os.path.isfile(recovered_jsonl), f"Missing required file: {recovered_jsonl}"

    recover_bin = "/tmp/recover"
    compile_res = run_checked(["go", "build", "-o", recover_bin, recover_src])
    assert compile_res.returncode == 0, f"Failed to compile {recover_src}:\n{compile_res.stderr}"
    assert os.path.isfile(recover_bin), f"Recovery binary not generated at {recover_bin}"

    wal_path = "/app/corrupted.wal"
    with open(wal_path, "rb") as f:
        original_wal = f.read()
    original_expected = expected_wal_payloads(original_wal)
    assert original_expected, "The supplied WAL unexpectedly has no valid records"

    execute_recovery(recover_bin, original_expected)

    dynamic_objects = [
        {"event": "probe", "id": secrets.token_hex(13), "sequence": 1},
        {"event": "alert", "id": secrets.token_hex(17), "sequence": 2, "ok": True},
        {"event": "close", "id": secrets.token_hex(9), "sequence": 3},
    ]
    encoded = [json.dumps(obj, separators=(",", ":")).encode() for obj in dynamic_objects]
    bad_payload = json.dumps({"event": "poison", "id": secrets.token_hex(20)}).encode()
    dynamic_wal = (
        wal_record(encoded[0])
        + b"\x00BROKEN_RANGE\xff\x10"
        + wal_record(bad_payload, (binascii.crc32(bad_payload) + 1) & 0xffffffff)
        + b"more-corruption"
        + wal_record(encoded[1])
        + b"partial-WAL"
        + wal_record(encoded[2])
        + b"WAL1" + struct.pack("<I", 4096) + b"truncated"
    )
    dynamic_expected = expected_wal_payloads(dynamic_wal)
    assert dynamic_expected == dynamic_objects

    try:
        with open(wal_path, "wb") as f:
            f.write(dynamic_wal)
        execute_recovery(recover_bin, dynamic_expected)
    finally:
        with open(wal_path, "wb") as f:
            f.write(original_wal)
        # Leave the requested output corresponding to the real incident WAL.
        if os.path.exists(recovered_jsonl):
            os.remove(recovered_jsonl)
        subprocess.run([recover_bin], capture_output=True, text=True, timeout=15)


TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
