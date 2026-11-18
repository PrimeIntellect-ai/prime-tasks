#!/bin/bash
set -e
mkdir -p /logs/verifier

# Preserve and instrument the supplied legacy executable so each request must
# actually invoke /app/legacy_etl.
if ! python3 - <<'PY'
from pathlib import Path
p = Path('/app/legacy_etl')
raise SystemExit(0 if p.is_file() and p.stat().st_mode & 0o111 and p.read_bytes()[:4] == b'\x7fELF' else 1)
PY
then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

ORIGINAL="/app/.legacy_etl.verifier.$$.${RANDOM}"
MARKER="/tmp/legacy_etl_calls.$$.${RANDOM}"
mv /app/legacy_etl "$ORIGINAL"
cat > /app/legacy_etl <<EOF
#!/bin/sh
printf 'called\n' >> '$MARKER'
exec '$ORIGINAL' "\$@"
EOF
chmod +x /app/legacy_etl
export LEGACY_ETL_MARKER="$MARKER"

cleanup() {
    rm -f /app/legacy_etl "$MARKER"
    if [ -e "$ORIGINAL" ]; then
        mv "$ORIGINAL" /app/legacy_etl
    fi
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
from pathlib import Path

import pytest
import requests

BASE_URL = "http://127.0.0.1:9090"
MARKER = Path(os.environ["LEGACY_ETL_MARKER"])


def call_count():
    if not MARKER.exists():
        return 0
    return len(MARKER.read_text().splitlines())


def post_csv(csv_data):
    before = call_count()
    try:
        response = requests.post(
            f"{BASE_URL}/process",
            data=csv_data,
            headers={"Content-Type": "text/csv"},
            timeout=10,
        )
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to /process endpoint: {e}")

    assert response.status_code == 200, (
        f"Expected status code 200, got {response.status_code}. "
        f"Response: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Expected JSON response from /process, got: {response.text}")

    assert call_count() > before, "/process did not invoke /app/legacy_etl"
    return data


def expected_from_rows(rows):
    result = []
    seen = set()
    for record_id, name, email, ssn in rows:
        if record_id in seen:
            continue
        seen.add(record_id)
        local, domain = email.split("@", 1)
        result.append({
            "record_id": record_id,
            "name": name,
            "email": local[0] + "*@" + domain,
            "ssn": re.sub(r"^\d{3}-\d{2}", "***-**", ssn),
        })
    return result


def test_health_endpoint():
    try:
        response = requests.get(f"{BASE_URL}/health", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to /health endpoint: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Expected JSON response from /health, got: {response.text}")

    assert data == {"status": "ok"}, f"Expected {{'status': 'ok'}}, got {data}"


def test_process_endpoint():
    csv_data = (
        "1,Alice,alice.smith@domain.com,111-22-3333\n"
        "2,Bob,bob@other.com,444-55-6666\n"
        "3,Charlie,c@test.com,777-88-9999\n"
    )
    data = post_csv(csv_data)

    assert isinstance(data, list), f"Expected response to be a JSON array, got {type(data)}"
    assert len(data) == 3, f"Expected exactly 3 records after deduplication, got {len(data)}"

    expected_records = [
        {"record_id": "1", "name": "Alice", "email": "a*@domain.com", "ssn": "***-**-3333"},
        {"record_id": "2", "name": "Bob", "email": "b*@other.com", "ssn": "***-**-6666"},
        {"record_id": "3", "name": "Charlie", "email": "c*@test.com", "ssn": "***-**-9999"},
    ]

    for expected, actual in zip(expected_records, data):
        assert actual.get("record_id") == expected["record_id"], f"Expected record_id {expected['record_id']}, got {actual.get('record_id')}"
        assert actual.get("name") == expected["name"], f"Expected name {expected['name']}, got {actual.get('name')}"
        assert actual.get("email") == expected["email"], f"Expected email {expected['email']}, got {actual.get('email')}"
        assert actual.get("ssn") == expected["ssn"], f"Expected ssn {expected['ssn']}, got {actual.get('ssn')}"


def test_randomized_inputs_and_first_occurrence_deduplication():
    token = secrets.token_hex(6)
    a, b, c, d, e, f = [f"{token}-{x}" for x in "abcdef"]
    domain = f"{secrets.token_hex(4)}.example"
    rows = [
        (a, f"Alpha{token}", f"alpha.long.{token}@{domain}", "102-34-5601"),
        (b, f"Beta{token}", f"b@{domain}", "213-45-6702"),
        (c, f"Gamma{token}", f"gamma_{token}@{domain}", "324-56-7803"),
        (a, f"Changed{token}", f"wrong_{token}@{domain}", "999-99-9999"),
        (d, f"Delta{token}", f"delta.{token}@{domain}", "435-67-8904"),
        (e, f"Epsilon{token}", f"epsilon{token}@{domain}", "546-78-9015"),
        (b, f"AlsoChanged{token}", f"bad_{token}@{domain}", "888-88-8888"),
        (f, f"Zeta{token}", f"z{token}@{domain}", "657-89-0126"),
    ]
    csv_data = "".join(",".join(row) + "\n" for row in rows)
    data = post_csv(csv_data)

    assert isinstance(data, list), f"Expected response to be a JSON array, got {type(data)}"
    assert data == expected_from_rows(rows)


def test_randomized_single_record():
    token = secrets.token_hex(8)
    rows = [(
        f"id-{token}",
        f"Name{token}",
        f"person.{token}@mail-{token}.example",
        "765-43-2109",
    )]
    data = post_csv("".join(",".join(row) + "\n" for row in rows))
    assert data == expected_from_rows(rows)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
