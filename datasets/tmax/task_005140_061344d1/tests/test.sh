#!/bin/bash
set -u
mkdir -p /logs/verifier
reward=0

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import socket
import subprocess
from collections import defaultdict
from decimal import Decimal
import pytest

RAW_PATH = "/home/user/raw_translations.tsv"
ACCEPTED_PATH = "/home/user/accepted_translations.tsv"


def normalize(text):
    return re.sub(r"[^a-z0-9 ]", "", text.lower())


def load_expected():
    rows = []
    with open(RAW_PATH, newline="", encoding="utf-8") as f:
        reader = csv.reader(f, delimiter="\t")
        for fields in reader:
            if not fields or not any(fields):
                continue
            if fields[0].strip().lower() == "id":
                continue
            assert len(fields) == 4, f"Malformed input row: {fields!r}"
            ident, lang, source, proposed = fields
            norm_source = normalize(source)
            norm_proposed = normalize(proposed)
            result = subprocess.run(
                ["/app/tqs", norm_source, norm_proposed],
                check=True,
                text=True,
                stdout=subprocess.PIPE,
            )
            score = Decimal(result.stdout.strip())
            rows.append({
                "id": ident,
                "lang": lang,
                "source": source,
                "proposed": proposed,
                "norm_source": norm_source,
                "norm_proposed": norm_proposed,
                "score": score,
            })

    passed = defaultdict(list)
    for row in rows:
        if row["score"] >= Decimal("0.50"):
            passed[row["lang"]].append(row)

    selected = []
    for lang_rows in passed.values():
        def id_key(row):
            ident = row["id"]
            return (0, int(ident)) if ident.isdigit() else (1, ident)
        lang_rows.sort(key=lambda row: (-row["score"], id_key(row)))
        selected.extend(lang_rows[:2])
    return rows, {row["id"]: row for row in selected}


ALL_ROWS, EXPECTED = load_expected()


def send_request(host, port, message):
    try:
        with socket.create_connection((host, port), timeout=2) as sock:
            sock.sendall(message.encode("utf-8"))
            response = sock.recv(1024).decode("utf-8")
            return response
    except Exception as e:
        pytest.fail(f"Failed to connect or communicate with service at {host}:{port}: {e}")


@pytest.mark.parametrize("request_str, expected_response", [
    ("FETCH 104\n", "Admin login ok\n"),
    ("FETCH 102\n", "Erreur system 404!\n"),
    ("FETCH 203\n", "Admin login ok\n"),
    ("FETCH 201\n", "Error system 404!\n"),
    ("FETCH 103\n", "ERROR\n"),
    ("FETCH 202\n", "ERROR\n"),
    ("FETCH 101\n", "ERROR\n"),
    ("FETCH 204\n", "ERROR\n"),
    ("FETCH 999\n", "ERROR\n"),
    ("INVALID CMD\n", "ERROR\n"),
])
def test_tcp_service(request_str, expected_response):
    host = "127.0.0.1"
    port = 9090
    actual_response = send_request(host, port, request_str)
    assert actual_response == expected_response, (
        f"For request {request_str!r}, expected {expected_response!r} "
        f"but got {actual_response!r}"
    )


def test_tcp_service_matches_recomputed_dataset():
    for row in ALL_ROWS:
        expected_response = (
            EXPECTED[row["id"]]["proposed"] + "\n"
            if row["id"] in EXPECTED else "ERROR\n"
        )
        actual = send_request("127.0.0.1", 9090, f"FETCH {row['id']}\n")
        assert actual == expected_response, (
            f"Recomputed result for ID {row['id']} should be {expected_response!r}, "
            f"got {actual!r}"
        )

    for request in ("FETCH 999999\n", "FETCH\n", "FETCH 104 extra\n", "INVALID CMD\n"):
        assert send_request("127.0.0.1", 9090, request) == "ERROR\n"


def test_accepted_translations_file_exists():
    assert os.path.isfile(ACCEPTED_PATH), (
        f"File {ACCEPTED_PATH} is missing. The processed dataset must be saved here."
    )


def test_accepted_translations_contents():
    with open(ACCEPTED_PATH, newline="", encoding="utf-8") as f:
        records = [row for row in csv.reader(f, delimiter="\t") if row and any(row)]

    assert records, "accepted_translations.tsv is empty"
    parsed = {}
    for index, fields in enumerate(records):
        first = fields[0].strip() if fields else ""
        if index == 0 and first.lower() == "id":
            continue
        assert first in EXPECTED, f"Unexpected or unselected row in accepted file: {fields!r}"
        assert first not in parsed, f"Duplicate accepted row for ID {first}"
        parsed[first] = fields

    assert set(parsed) == set(EXPECTED), (
        f"Accepted IDs were {sorted(parsed)}, expected {sorted(EXPECTED)}"
    )

    for ident, expected in EXPECTED.items():
        fields = parsed[ident]
        assert expected["lang"] in fields, f"Language missing or wrong for ID {ident}"
        assert expected["source"] in fields or expected["norm_source"] in fields, (
            f"Source text missing or wrong for ID {ident}"
        )
        assert expected["proposed"] in fields or expected["norm_proposed"] in fields, (
            f"Proposed text missing or wrong for ID {ident}"
        )

        numeric_values = []
        for field in fields[1:]:
            try:
                numeric_values.append(Decimal(field.strip()))
            except Exception:
                pass
        assert expected["score"] in numeric_values, (
            f"Correct normalized /app/tqs score {expected['score']} missing for ID {ident}"
        )
TEST_EOF

if [[ -f /home/user/serve.sh ]] && bash -n /home/user/serve.sh; then
    pkill -f '/home/user/serve[.]sh' 2>/dev/null || true
    pkill -f '[s]ocat.*9090' 2>/dev/null || true
    pkill -f '[n]c.*9090' 2>/dev/null || true
    sleep 0.2

    nohup bash /home/user/serve.sh >/tmp/serve-verifier.log 2>&1 &
    sleep 1

    if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
        reward=1
    fi
fi

echo "$reward" > /logs/verifier/reward.txt
