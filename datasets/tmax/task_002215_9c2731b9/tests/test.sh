#!/bin/bash
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

# Stop any pre-existing service so the submitted pipeline must start its own.
python3 - <<'PY' >/dev/null 2>&1 || true
import os, signal, time
inodes = set()
for table in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        with open(table) as f:
            next(f)
            for line in f:
                fields = line.split()
                if fields[1].rsplit(":", 1)[-1].upper() == "1F90" and fields[3] == "0A":
                    inodes.add(fields[9])
    except OSError:
        pass
pids = set()
for name in os.listdir("/proc"):
    if not name.isdigit():
        continue
    fd_dir = f"/proc/{name}/fd"
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(f"{fd_dir}/{fd}")
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                pids.add(int(name))
                break
    except OSError:
        pass
for pid in pids:
    try:
        os.kill(pid, signal.SIGTERM)
    except OSError:
        pass
time.sleep(0.3)
for pid in pids:
    try:
        os.kill(pid, signal.SIGKILL)
    except OSError:
        pass
PY

rm -f /home/user/data/processed/long_translations.csv \
      /home/user/data/processed/qa_sample.csv \
      /home/user/pipeline.log \
      /tmp/extractor_calls.txt \
      /tmp/pipeline_run_ok
printf '0\n' > /tmp/pipeline_run_ok

# Temporarily wrap the real extractor to prove the submitted DAG invokes it for
# every resource. The real binary is restored before behavioral verification.
WRAPPED=0
if [ -x /app/legacy_extractor ]; then
    if mv /app/legacy_extractor /app/legacy_extractor.real_for_verifier; then
        cat > /app/legacy_extractor <<'WRAP_EOF'
#!/bin/bash
arg="$1"
if [[ "$arg" = /* ]]; then
    resolved="$arg"
else
    resolved="$(realpath -m "$PWD/$arg")"
fi
printf '%s\n' "$resolved" >> /tmp/extractor_calls.txt
exec /app/legacy_extractor.real_for_verifier "$@"
WRAP_EOF
        chmod 755 /app/legacy_extractor
        WRAPPED=1
    fi
fi

if [ "$WRAPPED" -eq 1 ] && [ -f /home/user/run_pipeline.sh ]; then
    if timeout 30s bash /home/user/run_pipeline.sh >/tmp/pipeline_verifier_stdout.log 2>&1; then
        printf '1\n' > /tmp/pipeline_run_ok
    fi
fi

if [ "$WRAPPED" -eq 1 ]; then
    rm -f /app/legacy_extractor
    mv /app/legacy_extractor.real_for_verifier /app/legacy_extractor
fi

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import re
import subprocess
import time
from collections import Counter

import pandas as pd
import pytest
import requests

RESOURCE_DIR = "/home/user/data/resources"
LONG_PATH = "/home/user/data/processed/long_translations.csv"
QA_PATH = "/home/user/data/processed/qa_sample.csv"
LOCALES = ["en_US", "es_ES", "fr_FR", "ja_JP"]
PREFIX = "[UNTRANSLATED] "


def extractor_rows():
    """Derive the oracle by executing the shipped extractor on every .bin."""
    result = []
    start_re = re.compile(r"^([A-Z][A-Z0-9_]*),")
    resources = sorted(
        os.path.join(RESOURCE_DIR, name)
        for name in os.listdir(RESOURCE_DIR)
        if name.endswith(".bin")
    )
    assert resources, "No resource files found"

    for path in resources:
        raw = subprocess.check_output(["/app/legacy_extractor", path]).decode("utf-8")
        chunks = []
        current = None
        for physical in raw.splitlines(keepends=True):
            if physical.startswith("key,en_US,es_ES,fr_FR,ja_JP"):
                continue
            if start_re.match(physical):
                if current is not None:
                    chunks.append(current)
                current = physical
            elif current is not None:
                current += physical
        if current is not None:
            chunks.append(current)

        for chunk in chunks:
            # Remove the record terminator while preserving embedded newlines,
            # including a final embedded newline before that terminator.
            if chunk.endswith("\n"):
                chunk = chunk[:-1]
            if chunk.endswith("\r"):
                chunk = chunk[:-1]
            fields = chunk.split(",")
            assert len(fields) == 5, f"Could not reconstruct extractor row: {fields!r}"
            key, en_us, es_es, fr_fr, ja_jp = fields
            values = dict(zip(LOCALES, [en_us, es_es, fr_fr, ja_jp]))
            for locale in LOCALES:
                value = values[locale] if values[locale] != "" else PREFIX + en_us
                result.append((key, locale, value))
    return result


@pytest.fixture(scope="module")
def expected_rows():
    return extractor_rows()


def read_csv(path):
    with open(path, "r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        fieldnames = reader.fieldnames
        rows = list(reader)
    return fieldnames, rows


def test_pipeline_script_was_executed_and_used_extractor():
    script = "/home/user/run_pipeline.sh"
    assert os.path.isfile(script), f"Missing {script}"
    assert os.path.getsize(script) > 0, f"Empty {script}"
    with open("/tmp/pipeline_run_ok") as f:
        assert f.read().strip() == "1", "run_pipeline.sh failed, timed out, or did not return"

    expected_files = {
        os.path.realpath(os.path.join(RESOURCE_DIR, name))
        for name in os.listdir(RESOURCE_DIR)
        if name.endswith(".bin")
    }
    assert os.path.isfile("/tmp/extractor_calls.txt"), "Pipeline never invoked /app/legacy_extractor"
    with open("/tmp/extractor_calls.txt") as f:
        called = {os.path.realpath(line.strip()) for line in f if line.strip()}
    assert expected_files <= called, "Pipeline did not run the extractor on every .bin resource"

    assert os.path.isfile("/home/user/pipeline.log"), "Missing /home/user/pipeline.log"
    assert os.path.getsize("/home/user/pipeline.log") > 0, "pipeline.log is empty"


def test_long_translations_csv(expected_rows):
    assert os.path.isfile(LONG_PATH), f"Missing {LONG_PATH}"
    headers, rows = read_csv(LONG_PATH)
    assert headers, "CSV is empty or missing headers"
    stripped = [h.strip() for h in headers]
    assert "key" in stripped, "Missing 'key' column"
    assert "locale" in stripped, "Missing 'locale' column"
    assert "translation" in stripped, "Missing 'translation' column"
    assert stripped == ["key", "locale", "translation"], "Unexpected long CSV columns"
    assert len(rows) > 0, "No data rows in long_translations.csv"

    actual = [(row["key"], row["locale"], row["translation"]) for row in rows]
    assert Counter(actual) == Counter(expected_rows), \
        "Long CSV does not exactly match repaired, reshaped, and imputed extractor output"
    assert len(actual) == len(set((k, loc) for k, loc, _ in actual)), \
        "Duplicate key/locale rows found"
    assert {loc for _, loc, _ in actual} == set(LOCALES), "Locale set is incorrect"

    # Preserve and strengthen the original imputation assertion.
    for row in rows:
        if row["translation"].startswith(PREFIX):
            assert len(row["translation"]) > len(PREFIX), "Imputed string is empty after prefix"


def test_qa_sample_csv(expected_rows):
    assert os.path.isfile(QA_PATH), f"Missing {QA_PATH}"
    headers, qa_rows = read_csv(QA_PATH)
    assert headers and [h.strip() for h in headers] == ["key", "locale", "translation"]

    ordered_keys = []
    for key, _, _ in expected_rows:
        if key not in ordered_keys:
            ordered_keys.append(key)
    sample_count = int(len(ordered_keys) * 0.10)
    assert sample_count == 1, "Fixture should contain exactly one sampled key"
    sampled_keys = set(pd.Series(ordered_keys).sample(n=sample_count, random_state=42).tolist())
    expected_qa = [row for row in expected_rows if row[0] in sampled_keys]

    qa_keys = {row["key"] for row in qa_rows}
    assert len(qa_keys) > 0, "qa_sample.csv has no keys"
    expected_sample_size = int(len(ordered_keys) * 0.10)
    assert abs(len(qa_keys) - expected_sample_size) <= 1, \
        f"Expected ~{expected_sample_size} keys in QA sample, found {len(qa_keys)}"
    assert qa_keys == sampled_keys, "QA key selection does not match seed 42"

    actual_qa = [(row["key"], row["locale"], row["translation"]) for row in qa_rows]
    assert Counter(actual_qa) == Counter(expected_qa), \
        "QA CSV must contain every locale variant, and only those variants, for sampled keys"


def get_response(locale):
    url = "http://127.0.0.1:8080/api/v1/strings"
    last_error = None
    for _ in range(10):
        try:
            response = requests.get(url, params={"locale": locale}, timeout=2)
            if response.status_code == 200:
                return response
            last_error = f"HTTP {response.status_code}"
        except requests.RequestException as exc:
            last_error = str(exc)
        time.sleep(0.5)
    pytest.fail(f"Could not connect to HTTP server at 127.0.0.1:8080: {last_error}")


def test_http_server_endpoint(expected_rows):
    for locale in LOCALES:
        response = get_response(locale)
        data = response.json()
        assert isinstance(data, dict), "Response should be a JSON object"
        assert len(data) > 0, "Returned JSON object is empty"
        for key, value in data.items():
            assert isinstance(key, str), "Keys must be strings"
            assert isinstance(value, str), "Values must be strings"

        expected = {key: value for key, row_locale, value in expected_rows if row_locale == locale}
        assert data == expected, f"HTTP response is incorrect or not filtered for {locale}"

    fr_data = get_response("fr_FR").json()
    assert any(value.startswith(PREFIX) for value in fr_data.values()), \
        "Expected fallback values are absent from fr_FR response"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
