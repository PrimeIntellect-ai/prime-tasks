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
import csv
import io
import secrets
import string

import pytest
import requests

URL = "http://127.0.0.1:8000/process"
VALID_HEADERS = {"Authorization": "Bearer data-science-token"}


def levenshtein(a, b):
    previous = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        current = [i]
        for j, cb in enumerate(b, 1):
            current.append(min(
                current[-1] + 1,
                previous[j] + 1,
                previous[j - 1] + (ca != cb),
            ))
        previous = current
    return previous[-1]


def make_csv(rows):
    output = io.StringIO(newline="")
    writer = csv.writer(output, lineterminator="\r\n")
    writer.writerow(["id", "text_a", "text_b"])
    writer.writerows(rows)
    return output.getvalue()


def expected_report(rows):
    return "".join(
        f"[ID: {row_id}] Distance: {levenshtein(text_a, text_b)}\n"
        for row_id, text_a, text_b in rows
    )


def test_unauthorized_missing_header():
    """Test that requests without the Authorization header return 401."""
    data = "id,text_a,text_b\n1,a,a\n"
    try:
        response = requests.post(URL, data=data, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to the Nginx reverse proxy: {e}")

    assert response.status_code == 401, f"Expected HTTP 401 for missing auth, got {response.status_code}"


def test_unauthorized_invalid_header():
    """Test that requests with an invalid Authorization header return 401."""
    headers = {"Authorization": "Bearer wrong-token"}
    data = "id,text_a,text_b\n1,a,a\n"
    try:
        response = requests.post(URL, headers=headers, data=data, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to the Nginx reverse proxy: {e}")

    assert response.status_code == 401, f"Expected HTTP 401 for invalid auth, got {response.status_code}"


def test_successful_processing_with_newlines():
    """Retain the original embedded-newline regression case."""
    data = (
        "id,text_a,text_b\n"
        '1,"clean","clear"\n'
        '2,"line\nbreak","line\nbreak"\n'
        '3,"kitten","sitting"\n'
    )

    try:
        response = requests.post(URL, headers=VALID_HEADERS, data=data, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to the Nginx reverse proxy: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}. Response: {response.text}"

    expected_output = (
        "[ID: 1] Distance: 2\n"
        "[ID: 2] Distance: 0\n"
        "[ID: 3] Distance: 3\n"
    )
    assert response.text == expected_output, f"Response body did not match expected output.\nExpected:\n{expected_output}\nGot:\n{response.text}"


def test_randomized_standard_csv_processing():
    """Exercise unpredictable rows, quoted commas, quotes, and embedded newlines."""
    alphabet = string.ascii_letters + string.digits
    nonce = "".join(secrets.choice(alphabet) for _ in range(18))
    random_a = "".join(secrets.choice(alphabet) for _ in range(23))
    random_b = "".join(secrets.choice(alphabet) for _ in range(19))

    rows = [
        (f"r-{nonce}-1", f"prefix,{nonce}\nsecond line", f"prefix,{nonce}\nsecond lime"),
        (f"r-{nonce}-2", f'he said "{random_a}"\nthen left', f'he said "{random_b}"\nthen left'),
        (f"r-{nonce}-3", random_a, random_b),
        (f"r-{nonce}-4", "", f",quoted field\n{nonce}"),
        (f"r-{nonce}-5", f"one\ntwo\n{random_a},four", f"one\ntoo\n{random_a},four"),
        (f"r-{nonce}-6", f'comma, quote " and {nonce}', f'comma, quote " and {nonce}'),
    ]
    data = make_csv(rows)
    expected = expected_report(rows)

    try:
        response = requests.post(URL, headers=VALID_HEADERS, data=data, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to the Nginx reverse proxy: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}. Response: {response.text}"
    assert response.text == expected, f"Randomized CSV response mismatch.\nExpected:\n{expected}\nGot:\n{response.text}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
