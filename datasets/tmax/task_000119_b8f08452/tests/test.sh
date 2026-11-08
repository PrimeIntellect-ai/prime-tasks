#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import math
import os
import random
import re
import secrets
import stat
import string
import struct
import subprocess
import tempfile
import wave

import pytest

SCRIPT_PATH = "/home/user/pass_filter.sh"


def test_pass_filter_script_exists():
    script_path = SCRIPT_PATH
    assert os.path.isfile(script_path), f"Missing pass_filter.sh script: {script_path}"
    assert os.access(script_path, os.X_OK), f"Script is not executable: {script_path}"
    mode = os.lstat(script_path).st_mode
    assert stat.S_ISREG(mode), f"pass_filter.sh must be a regular file: {script_path}"


def test_adversarial_corpus():
    script_path = SCRIPT_PATH
    evil_dir = "/app/corpus/evil/"
    clean_dir = "/app/corpus/clean/"

    assert os.path.isdir(evil_dir), f"Missing evil corpus directory: {evil_dir}"
    assert os.path.isdir(clean_dir), f"Missing clean corpus directory: {clean_dir}"

    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]

    assert len(evil_files) > 0, "No evil files found to test."
    assert len(clean_files) > 0, "No clean files found to test."

    evil_bypassed = []
    clean_rejected = []

    for e_file in evil_files:
        result = subprocess.run(["bash", script_path, e_file], capture_output=True, text=True)
        if result.returncode != 1 or "REJECT" not in result.stdout:
            evil_bypassed.append(os.path.basename(e_file))

    for c_file in clean_files:
        result = subprocess.run(["bash", script_path, c_file], capture_output=True, text=True)
        if result.returncode != 0 or "ACCEPT" not in result.stdout:
            clean_rejected.append(os.path.basename(c_file))

    error_msgs = []
    if evil_bypassed:
        error_msgs.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_rejected:
        error_msgs.append(f"{len(clean_rejected)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_rejected)}")

    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def decode_dtmf(path):
    with wave.open(path, "rb") as audio:
        assert audio.getnchannels() == 1
        assert audio.getsampwidth() == 2
        rate = audio.getframerate()
        raw = audio.readframes(audio.getnframes())

    samples = struct.unpack("<%dh" % (len(raw) // 2), raw)
    lows = [697, 770, 852, 941]
    highs = [1209, 1336, 1477, 1633]
    keypad = {
        (697, 1209): "1", (697, 1336): "2", (697, 1477): "3", (697, 1633): "A",
        (770, 1209): "4", (770, 1336): "5", (770, 1477): "6", (770, 1633): "B",
        (852, 1209): "7", (852, 1336): "8", (852, 1477): "9", (852, 1633): "C",
        (941, 1209): "*", (941, 1336): "0", (941, 1477): "#", (941, 1633): "D",
    }

    def power(block, frequency):
        coeff = 2.0 * math.cos(2.0 * math.pi * frequency / rate)
        previous = previous2 = 0.0
        for sample in block:
            current = sample + coeff * previous - previous2
            previous2, previous = previous, current
        return previous2 * previous2 + previous * previous - coeff * previous * previous2

    frame_size = max(1, int(rate * 0.05))
    observed = []
    for offset in range(0, len(samples) - frame_size + 1, frame_size):
        block = samples[offset:offset + frame_size]
        rms = math.sqrt(sum(float(x) * x for x in block) / len(block))
        if rms < 500:
            observed.append(None)
            continue
        low = max(lows, key=lambda f: power(block, f))
        high = max(highs, key=lambda f: power(block, f))
        observed.append(keypad[(low, high)])

    decoded = []
    previous = None
    for symbol in observed:
        if symbol is not None and symbol != previous:
            decoded.append(symbol)
        previous = symbol
    return "".join(decoded)


def derive_rules():
    pin = decode_dtmf("/app/voicemail.wav")
    assert pin and pin.isdigit(), "Could not derive numeric DTMF PIN"

    with open("/app/legacy_validator", "rb") as binary:
        printable = re.findall(rb"[\x20-\x7e]{9,}", binary.read())
    backdoors = [value.decode("ascii") for value in printable if b"bckd" in value]
    assert len(backdoors) == 1, f"Expected one embedded backdoor string, found {len(backdoors)}"

    compromised = []
    with open("/app/auth_logs/auth.log", "r", encoding="utf-8") as log:
        for line in log:
            match = re.search(r"FAILED_ATTEMPT:\s+(\S+)", line)
            if match:
                compromised.append(base64.b64decode(match.group(1), validate=True).decode("utf-8"))
    assert compromised, "No compromised passwords found in auth log"
    return pin, backdoors[0], compromised


def random_safe(length, pin, backdoor, compromised):
    alphabet = string.ascii_letters + string.digits
    while True:
        value = "Z" + "".join(secrets.choice(alphabet) for _ in range(length - 1))
        if not value.startswith(pin) and backdoor not in value and value not in compromised:
            return value


def test_generated_rule_cases_at_unlabelled_paths():
    pin, backdoor, compromised = derive_rules()
    safe10 = random_safe(10, pin, backdoor, compromised)
    safe24 = random_safe(24, pin, backdoor, compromised)

    cases = [
        (pin + random_safe(12, pin, backdoor, compromised), 1, "REJECT"),
        (random_safe(12, pin, backdoor, compromised) + backdoor + random_safe(11, pin, backdoor, compromised), 1, "REJECT"),
        (random_safe(9, pin, backdoor, compromised), 1, "REJECT"),
        (safe10, 0, "ACCEPT"),
        (safe24, 0, "ACCEPT"),
        ("X" + pin + random_safe(12, pin, backdoor, compromised), 0, "ACCEPT"),
        (random_safe(10, pin, backdoor, compromised) + backdoor[:-1] + "X", 0, "ACCEPT"),
    ]
    for password in compromised:
        cases.append((password, 1, "REJECT"))
        extended = password + random_safe(10, pin, backdoor, compromised)
        if not extended.startswith(pin) and backdoor not in extended:
            cases.append((extended, 0, "ACCEPT"))

    random.SystemRandom().shuffle(cases)
    test_dir = tempfile.mkdtemp(prefix="pf_", dir="/tmp")
    failures = []
    for password, expected_code, expected_output in cases:
        path = os.path.join(test_dir, secrets.token_hex(12))
        with open(path, "w", encoding="utf-8", newline="") as handle:
            handle.write(password)
        result = subprocess.run([SCRIPT_PATH, path], capture_output=True, text=True, timeout=5)
        if result.returncode != expected_code or result.stdout.strip() != expected_output:
            failures.append(
                f"input {password!r}: expected ({expected_code}, {expected_output}), "
                f"got ({result.returncode}, {result.stdout.strip()!r})"
            )

    assert not failures, "Generated behavioral checks failed: " + " | ".join(failures)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
