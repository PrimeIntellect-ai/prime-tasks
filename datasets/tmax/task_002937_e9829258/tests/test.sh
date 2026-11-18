#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import glob
import json
import os
import random
import secrets
import shutil
import subprocess
import tempfile
import uuid

SCRIPT_PATH = "/home/user/filter.py"
DECODER_PATH = "/app/bin/temporal_decoder"
REQUIRED_KEYS = {"user_id", "obfuscated_ts", "event_type", "ip_address"}


def encode_ts(ts):
    return bytes((b ^ 0x42) for b in int(ts).to_bytes(4, "little")).hex()


def decode_ts(value):
    raw = bytes.fromhex(value)
    assert len(raw) == 4
    return int.from_bytes(bytes((b ^ 0x42) for b in raw), "little")


def event(ts, user="u0", kind="LOGIN_SUCCESS", ip="10.0.0.1"):
    return {
        "user_id": user,
        "obfuscated_ts": encode_ts(ts),
        "event_type": kind,
        "ip_address": ip,
    }


def oracle_is_evil(records):
    buckets = {}
    for record in records:
        if not isinstance(record, dict) or set(record) != REQUIRED_KEYS:
            return True
        if not all(isinstance(record[key], str) for key in REQUIRED_KEYS):
            return True
        ts = decode_ts(record["obfuscated_ts"])
        bucket = ts // 300 * 300
        state = buckets.setdefault(bucket, {"ips": collections.defaultdict(set), "failed": 0})
        state["ips"][record["user_id"]].add(record["ip_address"])
        if record["event_type"] == "LOGIN_FAILED":
            state["failed"] += 1

    return any(
        state["failed"] > 10 or any(len(ips) > 3 for ips in state["ips"].values())
        for state in buckets.values()
    )


def run_filter(path, timeout=10):
    return subprocess.run(
        ["python3", SCRIPT_PATH, path],
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def assert_result(path, evil):
    result = run_filter(path)
    expected_code = 1 if evil else 0
    expected_output = "EVIL" if evil else "CLEAN"
    assert result.returncode == expected_code, (
        f"{os.path.basename(path)}: expected status {expected_code}, got "
        f"{result.returncode}; stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert result.stdout.strip() == expected_output, (
        f"{os.path.basename(path)}: expected {expected_output}, got {result.stdout!r}"
    )


def test_filter_script_exists():
    assert os.path.isfile(SCRIPT_PATH), "The script /home/user/filter.py does not exist."


def test_adversarial_corpus():
    clean_files = glob.glob("/var/opt/clean_corpus/*.jsonl")
    evil_files = glob.glob("/var/opt/evil_corpus/*.jsonl")

    assert len(clean_files) > 0, "No clean corpus files found."
    assert len(evil_files) > 0, "No evil corpus files found."

    clean_modified = []
    for cf in clean_files:
        result = run_filter(cf)
        if result.returncode != 0 or result.stdout.strip() != "CLEAN":
            clean_modified.append(os.path.basename(cf))

    evil_bypassed = []
    for ef in evil_files:
        result = run_filter(ef)
        if result.returncode != 1 or result.stdout.strip() != "EVIL":
            evil_bypassed.append(os.path.basename(ef))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")

    if errors:
        assert False, " | ".join(errors)


def test_hidden_unlabelled_cases():
    rng = random.Random(secrets.randbits(128))
    base = rng.randrange(5_000_000, 10_000_000) * 300

    cases = []
    cases.append([])
    cases.append([
        event(base + i, "threshold-user", "LOGIN_FAILED" if i < 10 else "LOGIN_SUCCESS", f"10.1.0.{i % 3}")
        for i in range(14)
    ])
    cases.append([event(base + i, "many-ip-user", "LOGIN_SUCCESS", f"10.2.0.{i}") for i in range(4)])
    cases.append([event(base + i, f"user-{i}", "LOGIN_FAILED", "10.3.0.1") for i in range(11)])
    cases.append([
        event(base + 298, "boundary-user", "LOGIN_SUCCESS", "10.4.0.1"),
        event(base + 299, "boundary-user", "LOGIN_SUCCESS", "10.4.0.2"),
        event(base + 300, "boundary-user", "LOGIN_SUCCESS", "10.4.0.3"),
        event(base + 301, "boundary-user", "LOGIN_SUCCESS", "10.4.0.4"),
    ])
    cases.append(
        [event(base + i, f"before-{i}", "LOGIN_FAILED", "10.5.0.1") for i in range(10)]
        + [event(base + 300, "after", "LOGIN_FAILED", "10.5.0.1")]
    )
    cases.append([event(base, "exact-match", "LOGIN_FAILED_EXTRA", "10.6.0.1") for _ in range(15)])

    missing = event(base)
    del missing["ip_address"]
    cases.append([missing])
    extra = event(base)
    extra["unexpected"] = "value"
    cases.append([extra])
    wrong_type = event(base)
    wrong_type["user_id"] = 123
    cases.append([wrong_type])

    users = [f"r{n}" for n in range(8)]
    ips = [f"172.19.{n // 250}.{n % 250 + 1}" for n in range(20)]
    kinds = ["LOGIN_SUCCESS", "LOGIN_FAILED", "LOGIN", "LOGIN_FAILED_EXTRA"]
    for case_number in range(24):
        records = []
        for _ in range(rng.randint(1, 35)):
            ts = base + rng.randint(0, 3) * 300 + rng.randint(0, 299)
            records.append(event(ts, rng.choice(users), rng.choice(kinds), rng.choice(ips)))
        if case_number % 6 == 0:
            bucket = base + 600
            chosen = f"forced-{case_number}"
            records.extend(event(bucket + n, chosen, "LOGIN", f"203.0.113.{n + 1}") for n in range(4))
        elif case_number % 6 == 1:
            bucket = base + 900
            records.extend(event(bucket + n, f"aggregate-{n}", "LOGIN_FAILED", "198.51.100.1") for n in range(11))
        cases.append(records)

    observed_classes = set()
    with tempfile.TemporaryDirectory(prefix="audit_inputs_") as directory:
        for records in cases:
            name = uuid.uuid4().hex + ".jsonl"
            path = os.path.join(directory, name)
            with open(path, "w", encoding="utf-8") as handle:
                for record in records:
                    handle.write(json.dumps(record, separators=(",", ":")) + "\n")
            expected = oracle_is_evil(records)
            observed_classes.add(expected)
            assert_result(path, expected)

    assert observed_classes == {False, True}, "Hidden cases must exercise both classifications."


def test_decoder_is_used_for_every_valid_event():
    real_decoder = DECODER_PATH + ".verifier_real"
    audit_dir = tempfile.mkdtemp(prefix="decoder_audit_")
    audit_log = os.path.join(audit_dir, "calls")
    input_path = os.path.join(audit_dir, uuid.uuid4().hex + ".jsonl")
    base = secrets.randbelow(1_000_000) * 300 + 1_000_000_000
    records = [event(base + i, "decoder-user", "LOGIN_SUCCESS", f"10.9.0.{i % 2}") for i in range(7)]
    with open(input_path, "w", encoding="utf-8") as handle:
        for record in records:
            handle.write(json.dumps(record) + "\n")

    assert not os.path.exists(real_decoder), f"Unexpected path exists: {real_decoder}"
    os.rename(DECODER_PATH, real_decoder)
    try:
        with open(DECODER_PATH, "w", encoding="utf-8") as wrapper:
            wrapper.write("#!/bin/sh\n")
            wrapper.write("printf '%s\\n' \"$1\" >> \"$FILTER_DECODER_AUDIT\"\n")
            wrapper.write(f"exec {real_decoder} \"$@\"\n")
        os.chmod(DECODER_PATH, 0o755)

        env = os.environ.copy()
        env["FILTER_DECODER_AUDIT"] = audit_log
        result = subprocess.run(
            ["python3", SCRIPT_PATH, input_path],
            capture_output=True,
            text=True,
            timeout=10,
            env=env,
        )
        assert result.returncode == 0 and result.stdout.strip() == "CLEAN", (
            f"Decoder-use case was misclassified: status={result.returncode}, "
            f"stdout={result.stdout!r}, stderr={result.stderr!r}"
        )
        calls = []
        if os.path.exists(audit_log):
            with open(audit_log, encoding="utf-8") as handle:
                calls = [line.rstrip("\n") for line in handle]
        expected_calls = [record["obfuscated_ts"] for record in records]
        assert collections.Counter(calls) == collections.Counter(expected_calls), (
            "The temporal decoder must be invoked once for every valid event; "
            f"expected {expected_calls!r}, observed {calls!r}"
        )
    finally:
        if os.path.exists(DECODER_PATH):
            os.remove(DECODER_PATH)
        if os.path.exists(real_decoder):
            os.rename(real_decoder, DECODER_PATH)
        shutil.rmtree(audit_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
