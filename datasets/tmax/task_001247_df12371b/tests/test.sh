#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import hashlib
import json
import os
import secrets
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

import pytest

SANITIZER = "/home/user/csv_sanitizer"
REQUIRED_COLUMNS = ["user_id", "timestamp", "transaction_amount"]


def expected_records(path):
    with open(path, "r", encoding="utf-8", newline="") as src:
        reader = csv.reader(src)
        header = next(reader)
        indexes = {name: header.index(name) for name in REQUIRED_COLUMNS}
        seen = set()
        records = []
        for row in reader:
            digest = hashlib.sha256("".join(row).encode("utf-8")).hexdigest()
            if digest in seen:
                continue
            seen.add(digest)
            records.append({name: row[indexes[name]] for name in REQUIRED_COLUMNS})
        return records


def run_and_load(input_path, output_path):
    result = subprocess.run(
        [SANITIZER, input_path, output_path], capture_output=True, timeout=30
    )
    assert result.returncode == 0, (
        f"Sanitizer failed for {input_path} with exit code {result.returncode}: "
        f"{result.stderr.decode(errors='replace')}"
    )
    with open(output_path, "r", encoding="utf-8") as out_f:
        data = json.load(out_f)
    assert isinstance(data, list), "Sanitizer output is not a JSON array"
    return data


def test_nginx_upload():
    start_script = "/app/start_services.sh"
    if os.path.exists(start_script):
        # The agent may already have started the services. In that case a second
        # nginx invocation can fail because the port is in use, so exercise the
        # live endpoint rather than treating that harmless condition as failure.
        subprocess.run([start_script], capture_output=True)
        time.sleep(3)

    row = b"1,2021-01-01,100.00\n"
    num_rows = (5 * 1024 * 1024) // len(row)
    csv_data = b"user_id,timestamp,transaction_amount\n" + (row * num_rows)

    token = secrets.token_hex(8)
    filename = f"verifier-large-{token}.csv"
    boundary = f"----VerifierBoundary{token}"
    body = (
        f"--{boundary}\r\n"
        f"Content-Disposition: form-data; name=\"file\"; filename=\"{filename}\"\r\n"
        "Content-Type: text/csv\r\n\r\n"
    ).encode() + csv_data + f"\r\n--{boundary}--\r\n".encode()

    req = urllib.request.Request(
        "http://localhost:8080/upload",
        data=body,
        method="POST",
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            assert response.status == 200, (
                f"Expected 200 OK for 5MB upload, got {response.status}"
            )
    except urllib.error.HTTPError as e:
        pytest.fail(
            f"Upload failed with HTTP {e.code}: {e.reason}. "
            "Nginx client_max_body_size might not be configured correctly."
        )
    except Exception as e:
        pytest.fail(f"Upload failed: {e}")

    uploaded = os.path.join("/app/uploads", filename)
    assert os.path.isfile(uploaded), "Flask did not save the multipart upload"
    assert os.path.getsize(uploaded) == len(csv_data), "Saved upload has the wrong size"


def test_csv_sanitizer_clean_corpus():
    assert os.path.isfile(SANITIZER), f"Sanitizer tool missing at {SANITIZER}"
    assert os.access(SANITIZER, os.X_OK), f"Sanitizer tool at {SANITIZER} is not executable"

    clean_dir = "/app/tests/corpus/clean/"
    assert os.path.isdir(clean_dir), f"Clean corpus directory missing at {clean_dir}"
    clean_files = [f for f in os.listdir(clean_dir) if f.endswith(".csv")]
    assert len(clean_files) > 0, "No clean corpus files found"

    failed_clean = []
    for name in clean_files:
        input_path = os.path.join(clean_dir, name)
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            output_path = tmp.name
        try:
            data = run_and_load(input_path, output_path)
            assert data == expected_records(input_path), (
                f"{name} did not produce the required extracted records"
            )
            for item in data:
                assert set(REQUIRED_COLUMNS).issubset(item), (
                    f"{name} output is missing a required key"
                )
        except Exception as e:
            failed_clean.append(f"{name} ({e})")
        finally:
            if os.path.exists(output_path):
                os.unlink(output_path)

    if failed_clean:
        pytest.fail(
            f"{len(failed_clean)} of {len(clean_files)} clean modified/failed: "
            + ", ".join(failed_clean)
        )


def test_csv_sanitizer_generated_parsing_extraction_and_deduplication():
    token = secrets.token_hex(12)
    headers = ["ignored_before", "transaction_amount", "user_id", "timestamp", "other"]
    first = [
        f"note,{token}\nsecond line with \"quote\"",
        "101.25",
        f"user-{token}-1",
        "2026-07-01T10:11:12Z",
        "alpha",
    ]
    same_extracted_different_ignored = [
        f"different-{token}",
        "101.25",
        f"user-{token}-1",
        "2026-07-01T10:11:12Z",
        "beta,with,commas",
    ]
    third = [
        "plain",
        "0.00",
        f"user-{token}-2",
        "2026-07-02T00:00:00Z",
        "embedded\nnewline",
    ]
    rows = [first, first, same_extracted_different_ignored, third, third]

    with tempfile.TemporaryDirectory() as tmpdir:
        input_path = os.path.join(tmpdir, "generated.csv")
        output_path = os.path.join(tmpdir, "generated.json")
        with open(input_path, "w", encoding="utf-8", newline="") as out:
            writer = csv.writer(out, lineterminator="\n")
            writer.writerow(headers)
            writer.writerows(rows)

        data = run_and_load(input_path, output_path)
        expected = expected_records(input_path)
        assert len(expected) == 3
        assert data == expected, (
            "Sanitizer did not correctly parse quoted CSV, extract named columns, "
            "or deduplicate complete rows"
        )


def test_csv_sanitizer_evil_corpus():
    assert os.path.isfile(SANITIZER), f"Sanitizer tool missing at {SANITIZER}"

    evil_dir = "/app/tests/corpus/evil/"
    assert os.path.isdir(evil_dir), f"Evil corpus directory missing at {evil_dir}"
    evil_files = [f for f in os.listdir(evil_dir) if f.endswith(".csv")]
    assert len(evil_files) > 0, "No evil corpus files found"

    failed_evil = []
    for name in evil_files:
        input_path = os.path.join(evil_dir, name)
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            output_path = tmp.name
        result = subprocess.run([SANITIZER, input_path, output_path], capture_output=True)
        if result.returncode == 0:
            failed_evil.append(name)
        if os.path.exists(output_path):
            os.unlink(output_path)

    if failed_evil:
        pytest.fail(
            f"{len(failed_evil)} of {len(evil_files)} evil bypassed: "
            + ", ".join(failed_evil)
        )


def test_csv_sanitizer_rejects_all_injection_prefixes_without_output():
    token = secrets.token_hex(10)
    for index, prefix in enumerate(["=", "+", "-", "@"]):
        with tempfile.TemporaryDirectory() as tmpdir:
            input_path = os.path.join(tmpdir, f"evil-{index}.csv")
            output_path = os.path.join(tmpdir, "must-not-exist.json")
            with open(input_path, "w", encoding="utf-8", newline="") as out:
                writer = csv.writer(out, lineterminator="\n")
                writer.writerow(["user_id", "timestamp", "transaction_amount", "other"])
                writer.writerow([
                    f"user-{token}-{index}",
                    "2026-08-01T00:00:00Z",
                    "12.34",
                    prefix + f"payload,{token}\ncontinued",
                ])

            result = subprocess.run(
                [SANITIZER, input_path, output_path], capture_output=True, timeout=30
            )
            assert result.returncode != 0, (
                f"Sanitizer accepted a field beginning with {prefix!r}"
            )
            assert not os.path.exists(output_path), (
                "Sanitizer created an output file for malicious input"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
