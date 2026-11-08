#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import random
import re
import secrets
import time

import pytest
import requests

URL = "http://127.0.0.1:8080/"


def wait_for_server():
    for _ in range(10):
        try:
            requests.get(URL, timeout=1)
            return True
        except requests.exceptions.RequestException:
            pass
        time.sleep(0.5)
    return False


def test_server_running():
    # We just need it to accept connections; a GET might fail with 400 or something, but the connection should succeed
    try:
        requests.post(URL, data="", timeout=2)
    except requests.exceptions.ConnectionError:
        pytest.fail("Server is not listening on 127.0.0.1:8080")


def test_payload_1():
    payload = (
        '{"id": "1", "text": "Hello", "max_chars": 10}\n'
        '{"id": "2", "text": "こんにちは", "max_chars": 3}\n'
        '{"id": "3", "text": "Hello \\uD83C\\uDF0E", "max_chars": 10}\n'
        '{"id": "4", "text": "café", "max_chars": 4}\n'
        '{"id": "5", "text": "a", "max_chars": 1}\n'
    )

    try:
        response = requests.post(URL, data=payload, timeout=5)
    except Exception as e:
        pytest.fail(f"Request failed: {e}")

    assert response.status_code == 200, f"Expected status 200, got {response.status_code}. Body: {response.text}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    assert data.get("valid_count") == 4, f"Expected valid_count=4, got {data.get('valid_count')}"
    assert data.get("invalid_count") == 1, f"Expected invalid_count=1, got {data.get('invalid_count')}"
    assert data.get("avg_valid_len") == 4.25, f"Expected avg_valid_len=4.25, got {data.get('avg_valid_len')}"
    assert data.get("rolling_avg_3") == 4.00, f"Expected rolling_avg_3=4.00, got {data.get('rolling_avg_3')}"


def test_payload_2():
    payload = (
        '{"id": "1", "text": "テスト", "max_chars": 5}\n'
        '{"id": "2", "text": "\\uD83D\\uDE00", "max_chars": 0}\n'
        '{"id": "3", "text": "a", "max_chars": 10}\n'
        '{"id": "4", "text": "b", "max_chars": 10}\n'
        '{"id": "5", "text": "c", "max_chars": 10}\n'
        '{"id": "6", "text": "d", "max_chars": 10}\n'
    )

    try:
        response = requests.post(URL, data=payload, timeout=5)
    except Exception as e:
        pytest.fail(f"Request failed: {e}")

    assert response.status_code == 200, f"Expected status 200, got {response.status_code}. Body: {response.text}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    assert data.get("valid_count") == 5, f"Expected valid_count=5, got {data.get('valid_count')}"
    assert data.get("invalid_count") == 1, f"Expected invalid_count=1, got {data.get('invalid_count')}"
    assert data.get("avg_valid_len") == 1.40, f"Expected avg_valid_len=1.40, got {data.get('avg_valid_len')}"
    assert data.get("rolling_avg_3") == 1.00, f"Expected rolling_avg_3=1.00, got {data.get('rolling_avg_3')}"


def assert_computed_summary(response, records):
    assert response.status_code == 200, response.text
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    expected_keys = {"valid_count", "invalid_count", "avg_valid_len", "rolling_avg_3"}
    assert isinstance(data, dict)
    assert set(data) == expected_keys, f"Unexpected response structure: {data}"
    assert type(data["valid_count"]) is int
    assert type(data["invalid_count"]) is int

    valid_lengths = [len(item["text"]) for item in records if len(item["text"]) <= item["max_chars"]]
    invalid_count = len(records) - len(valid_lengths)
    avg = sum(valid_lengths) / len(valid_lengths) if valid_lengths else 0.0
    rolling = sum(valid_lengths[-3:]) / len(valid_lengths[-3:]) if valid_lengths else 0.0

    assert data["valid_count"] == len(valid_lengths)
    assert data["invalid_count"] == invalid_count
    assert isinstance(data["avg_valid_len"], (int, float)) and not isinstance(data["avg_valid_len"], bool)
    assert isinstance(data["rolling_avg_3"], (int, float)) and not isinstance(data["rolling_avg_3"], bool)
    # Values serialized to two decimal places must be within half a cent of the exact average.
    assert abs(float(data["avg_valid_len"]) - avg) <= 0.0050001
    assert abs(float(data["rolling_avg_3"]) - rolling) <= 0.0050001

    for field in ("avg_valid_len", "rolling_avg_3"):
        matches = re.findall(rf'"{field}"\s*:\s*-?(?:0|[1-9]\d*)\.\d{{2}}(?=\s*[,}}])', response.text)
        assert len(matches) == 1, f"{field} must be formatted with exactly two decimal places: {response.text}"


def send_generated_batch(records, escaped_flags):
    lines = [
        json.dumps(item, ensure_ascii=escaped, separators=(",", ":"))
        for item, escaped in zip(records, escaped_flags)
    ]
    payload = ("\n".join(lines) + "\n").encode("utf-8")
    try:
        response = requests.post(URL, data=payload, timeout=5)
    except Exception as exc:
        pytest.fail(f"Generated request failed: {exc}")
    assert_computed_summary(response, records)


def test_randomized_unicode_validation_and_rolling_aggregation():
    rng = random.Random(secrets.randbits(128))
    alphabet = list("abcdefghijklmnopqrstuvwxyz") + ["é", "ø", "λ", "Ж", "あ", "界", "م", "😀", "🌍", "🧪"]
    unicode_alphabet = ["é", "ø", "λ", "Ж", "あ", "界", "م", "😀", "🌍", "🧪"]

    def random_text(length):
        return "".join(rng.choice(alphabet) for _ in range(length))

    for batch_number in range(7):
        count = rng.randint(9, 15)
        records = []
        escaped_flags = []
        for index in range(count):
            length = rng.randint(1, 14)
            text = random_text(length)
            max_chars = rng.randint(0, 15)
            records.append({
                "id": f"{secrets.token_hex(5)}-{batch_number}-{index}",
                "text": text,
                "max_chars": max_chars,
            })
            escaped_flags.append(bool(rng.getrandbits(1)))

        # Guarantee both raw and escaped non-ASCII JSON, both outcomes, and
        # several final valid records whose lengths must drive the rolling value.
        records[0]["text"] = rng.choice(unicode_alphabet) + random_text(rng.randint(2, 7))
        records[0]["max_chars"] = len(records[0]["text"]) - 1
        escaped_flags[0] = True

        records[1]["text"] = rng.choice(unicode_alphabet) + random_text(rng.randint(1, 6))
        records[1]["max_chars"] = len(records[1]["text"])
        escaped_flags[1] = False

        records[-4]["text"] = random_text(rng.randint(2, 8))
        records[-4]["max_chars"] = len(records[-4]["text"]) - 1
        for offset, length in zip((-3, -2, -1), (rng.randint(1, 3), rng.randint(7, 11), rng.randint(3, 6))):
            records[offset]["text"] = random_text(length)
            records[offset]["max_chars"] = length + rng.randint(0, 2)

        send_generated_batch(records, escaped_flags)


def test_randomized_rolling_average_with_fewer_than_three_valid_lines():
    rng = random.Random(secrets.randbits(128))
    first = "😀" + "界" * rng.randint(1, 4)
    valid_one = "é" * rng.randint(1, 6)
    third = "🌍" + "あ" * rng.randint(2, 6)
    valid_two = "λ" * rng.randint(7, 11)
    records = [
        {"id": secrets.token_hex(6), "text": first, "max_chars": len(first) - 1},
        {"id": secrets.token_hex(6), "text": valid_one, "max_chars": len(valid_one)},
        {"id": secrets.token_hex(6), "text": third, "max_chars": len(third) - 1},
        {"id": secrets.token_hex(6), "text": valid_two, "max_chars": len(valid_two) + 1},
    ]
    send_generated_batch(records, [True, False, False, True])
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
