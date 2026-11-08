#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import importlib.util
import os

STANDARD_ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"


def calculate_f1(true_positives, false_positives, false_negatives):
    if true_positives == 0:
        return 0.0
    precision = true_positives / (true_positives + false_positives)
    recall = true_positives / (true_positives + false_negatives)
    return 2 * (precision * recall) / (precision + recall)


def standard_b58decode(value):
    number = 0
    for char in value:
        number = number * 58 + STANDARD_ALPHABET.index(char)
    decoded = number.to_bytes((number.bit_length() + 7) // 8, "big") if number else b""
    leading_zeroes = len(value) - len(value.lstrip("1"))
    return b"\x00" * leading_zeroes + decoded


def derive_expected_data():
    expected = {}
    with open('/home/user/upload_logs.txt', 'r') as log_file:
        for raw_line in log_file:
            parts = [part.strip() for part in raw_line.rstrip('\n').split('|')]
            assert len(parts) == 4, f"Malformed source log line: {raw_line!r}"
            _, ip, auth_hash, encoded_payload = parts
            payload = standard_b58decode(encoded_payload).decode('utf-8')
            lowered = payload.lower()
            malicious = any(pattern in lowered for pattern in ('../', '..\\', '..%2f', '..%5c'))
            if not malicious:
                continue

            cracked_pin = None
            for number in range(10000):
                candidate = f"{number:04d}"
                if hashlib.md5(candidate.encode()).hexdigest() == auth_hash:
                    cracked_pin = candidate
                    break
            assert cracked_pin is not None, f"Could not derive PIN for malicious log entry {ip}"
            expected[ip] = (cracked_pin, payload)
    return expected


def test_suspects_f1_score():
    suspects_path = '/home/user/suspects.txt'
    assert os.path.isfile(suspects_path), f"Output file missing at {suspects_path}"

    expected_data = derive_expected_data()

    with open(suspects_path, 'r') as f:
        lines = f.read().splitlines()

    parsed_agent_data = {}
    for line in lines:
        if not line.strip():
            continue
        parts = line.split(',', 2)
        if len(parts) == 3:
            parsed_agent_data[parts[0]] = (parts[1], parts[2])

    expected_ips = set(expected_data.keys())
    agent_ips = set(parsed_agent_data.keys())

    tp = 0
    for ip in expected_ips.intersection(agent_ips):
        if parsed_agent_data[ip] == expected_data[ip]:
            tp += 1

    fp = len(agent_ips - expected_ips)
    fn = len(expected_ips) - tp
    f1 = calculate_f1(tp, fp, fn)

    assert f1 >= 0.95, f"F1 score {f1:.2f} is below the threshold of 0.95. TP: {tp}, FP: {fp}, FN: {fn}"


def test_base58_fixed():
    init_path = '/app/base58-2.1.1/__init__.py'
    assert os.path.isfile(init_path), f"Vendored package missing at {init_path}"

    spec = importlib.util.spec_from_file_location(
        'vendored_base58', init_path,
        submodule_search_locations=['/app/base58-2.1.1']
    )
    assert spec is not None and spec.loader is not None, "Could not load vendored base58 package"
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    alphabet = getattr(module, 'BITCOIN_ALPHABET', None)
    if isinstance(alphabet, str):
        alphabet = alphabet.encode()
    assert alphabet == STANDARD_ALPHABET.encode(), "The active BITCOIN_ALPHABET is not standard"

    assert module.b58encode(b'\x00') == b'1', "Vendored b58encode does not use the standard alphabet"
    assert module.b58decode('1') == b'\x00', "Vendored b58decode does not use the standard alphabet"

    with open('/home/user/upload_logs.txt', 'r') as log_file:
        for raw_line in log_file:
            encoded_payload = raw_line.rstrip('\n').split('|')[3].strip()
            expected = standard_b58decode(encoded_payload)
            assert module.b58decode(encoded_payload) == expected, \
                f"Vendored package decoded {encoded_payload!r} incorrectly"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
