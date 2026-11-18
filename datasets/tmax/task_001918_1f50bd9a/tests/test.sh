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
import math
import os
import subprocess
import unicodedata

import pytest
import requests

AUTH_HEADER = {"Authorization": "Bearer ds_secret_token"}
BASE_URL = "http://127.0.0.1:8000"

EXPECTED = [
    {"id": 1, "category": "A", "raw_text": unicodedata.normalize("NFKC", "café"), "value": 10.0, "rolling_avg": 10.0},
    {"id": 2, "category": "B", "raw_text": unicodedata.normalize("NFKC", "tést"), "value": 15.0, "rolling_avg": 12.5},
    {"id": 3, "category": "A", "raw_text": unicodedata.normalize("NFKC", "fußball"), "value": 20.0, "rolling_avg": 15.0},
    {"id": 4, "category": "B", "raw_text": unicodedata.normalize("NFKC", "æther"), "value": 25.0, "rolling_avg": 20.0},
]


def test_cron_schedule_file():
    path = "/home/user/cron_schedule.txt"
    assert os.path.exists(path), f"File {path} does not exist"
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "0 2 * * *", f"Expected cron schedule '0 2 * * *', got '{content}'"


def test_cleaned_data_file_exists_and_matches_processed_data():
    path = "/home/user/cleaned_data.json"
    assert os.path.isfile(path), f"File {path} does not exist or is not a regular file"
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    assert data == EXPECTED, f"Unexpected contents in {path}: {data!r}"


def test_api_auth_required():
    try:
        resp = requests.get(f"{BASE_URL}/api/config", timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to {BASE_URL}: {e}")
    assert resp.status_code == 401, f"Expected 401 Unauthorized when missing auth header, got {resp.status_code}"


@pytest.mark.parametrize("endpoint", ["/api/config", "/api/data"])
@pytest.mark.parametrize("headers", [{}, {"Authorization": "Bearer incorrect_token"}])
def test_api_rejects_missing_and_incorrect_auth(endpoint, headers):
    try:
        resp = requests.get(f"{BASE_URL}{endpoint}", headers=headers, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to {BASE_URL}: {e}")
    assert resp.status_code == 401, (
        f"Expected 401 Unauthorized for {endpoint} with headers {headers}, "
        f"got {resp.status_code}"
    )


def test_api_config():
    try:
        resp = requests.get(f"{BASE_URL}/api/config", headers=AUTH_HEADER, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to {BASE_URL}: {e}")
    assert resp.status_code == 200, f"Expected 200 OK, got {resp.status_code}"
    data = resp.json()
    assert data.get("cron") == "0 2 * * *", f"Incorrect cron in config: {data.get('cron')}"
    assert data.get("strata_size") == 2, f"Incorrect strata_size in config: {data.get('strata_size')}"
    assert data.get("window") == 3, f"Incorrect window in config: {data.get('window')}"


def test_api_data():
    try:
        resp = requests.get(f"{BASE_URL}/api/data", headers=AUTH_HEADER, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to {BASE_URL}: {e}")
    assert resp.status_code == 200, f"Expected 200 OK, got {resp.status_code}"
    data = resp.json()
    assert isinstance(data, list), "Expected a JSON list of records"
    assert len(data) == 4, f"Expected 4 records after stratified sampling, got {len(data)}"

    for i, exp in enumerate(EXPECTED):
        record = data[i]
        assert record.get("id") == exp["id"], f"Row {i}: Expected id {exp['id']}, got {record.get('id')}"
        assert record.get("category") == exp["category"], f"Row {i}: Expected category {exp['category']}, got {record.get('category')}"
        assert record.get("raw_text") == exp["raw_text"], f"Row {i}: Expected raw_text {exp['raw_text']}, got {record.get('raw_text')}"
        assert record.get("value") == exp["value"], f"Row {i}: Expected value {exp['value']}, got {record.get('value')}"
        assert record.get("rolling_avg") == exp["rolling_avg"], f"Row {i}: Expected rolling_avg {exp['rolling_avg']}, got {record.get('rolling_avg')}"

    with open("/home/user/cleaned_data.json", "r", encoding="utf-8") as f:
        assert data == json.load(f), "The /api/data response does not match cleaned_data.json"


def _candidate_python_scripts():
    roots = ["/home/user", "/app", "/workspace", "/tmp"]
    candidates = []
    this_test = os.path.realpath(__file__)
    excluded_parts = {".local", ".venv", "venv", "site-packages", "__pycache__", ".pytest_cache"}

    for root in roots:
        if not os.path.isdir(root):
            continue
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d not in excluded_parts]
            if any(part in excluded_parts for part in dirpath.split(os.sep)):
                continue
            for name in filenames:
                if not name.endswith(".py"):
                    continue
                path = os.path.join(dirpath, name)
                if os.path.realpath(path) == this_test or not os.path.isfile(path):
                    continue
                try:
                    source = open(path, "r", encoding="utf-8").read()
                    compile(source, path, "exec")
                except (OSError, UnicodeError, SyntaxError):
                    continue
                lower = source.lower()
                if any(token in lower for token in (
                    "raw_data.csv", "pipeline_config.png", "cleaned_data.json",
                    "cron_schedule.txt", "tesseract", "rolling_avg"
                )):
                    server_only = ("serve_forever" in lower or "app.run" in lower or "uvicorn.run" in lower)
                    candidates.append((server_only, path))

    return [path for _, path in sorted(set(candidates), key=lambda item: (item[0], item[1]))]


def _read_dynamic_outputs(expected):
    try:
        with open("/home/user/cleaned_data.json", "r", encoding="utf-8") as f:
            records = json.load(f)
        with open("/home/user/cron_schedule.txt", "r", encoding="utf-8") as f:
            cron = f.read().strip()
    except (OSError, ValueError):
        return False

    if cron != "17 5 * * 1" or not isinstance(records, list) or len(records) != len(expected):
        return False
    for actual, wanted in zip(records, expected):
        for key in ("id", "category", "raw_text"):
            if actual.get(key) != wanted[key]:
                return False
        for key in ("value", "rolling_avg"):
            value = actual.get(key)
            if not isinstance(value, (int, float)) or not math.isclose(value, wanted[key], rel_tol=1e-9, abs_tol=1e-9):
                return False
    return True


def test_reusable_pipeline_on_changed_inputs():
    scripts = _candidate_python_scripts()
    assert scripts, "No reusable Python pipeline script was found"

    paths = [
        "/app/raw_data.csv",
        "/app/pipeline_config.png",
        "/home/user/cleaned_data.json",
        "/home/user/cron_schedule.txt",
    ]
    backups = {}
    for path in paths:
        backups[path] = open(path, "rb").read() if os.path.exists(path) else None

    expected = [
        {"id": 10, "category": "B", "raw_text": unicodedata.normalize("NFKC", "éclair"), "value": 3.0, "rolling_avg": 3.0},
        {"id": 15, "category": "C", "raw_text": unicodedata.normalize("NFKC", "Ｎａｉｖｅ"), "value": 5.0, "rolling_avg": 4.0},
        {"id": 20, "category": "A", "raw_text": unicodedata.normalize("NFKC", "ﬁle"), "value": 6.0, "rolling_avg": 5.5},
    ]

    try:
        with open("/app/raw_data.csv", "w", encoding="utf-8") as f:
            f.write(
                "id,category,raw_text,value\n"
                "30,A,Ａlpha,9.0\n"
                "10,B,éclair,3.0\n"
                "20,A,ﬁle,6.0\n"
                "40,B,omega,12.0\n"
                "15,C,Ｎａｉｖｅ,5.0\n"
                "35,C,résumé,10.0\n"
            )
        subprocess.run([
            "convert", "-size", "900x200", "xc:white", "-font", "DejaVu-Sans",
            "-pointsize", "24", "-fill", "black", "-draw",
            "text 50,100 'CONFIG: STRATA_SIZE=1, WINDOW=2, CRON=17 5 * * 1'",
            "/app/pipeline_config.png"
        ], check=True, timeout=10)

        for output in ("/home/user/cleaned_data.json", "/home/user/cron_schedule.txt"):
            try:
                os.unlink(output)
            except FileNotFoundError:
                pass

        errors = []
        passed = False
        for _ in range(2):
            for script in scripts:
                try:
                    result = subprocess.run(
                        ["timeout", "4s", "python3", script],
                        cwd=os.path.dirname(script) or "/",
                        stdout=subprocess.PIPE,
                        stderr=subprocess.STDOUT,
                        text=True,
                        timeout=6,
                    )
                    if result.returncode not in (0, 124):
                        errors.append(f"{script}: exit {result.returncode}: {result.stdout[-500:]}")
                except subprocess.TimeoutExpired:
                    errors.append(f"{script}: execution timeout")
                if _read_dynamic_outputs(expected):
                    passed = True
                    break
            if passed:
                break

        assert passed, (
            "The submitted Python pipeline did not regenerate correct outputs from changed CSV and OCR configuration inputs. "
            + " | ".join(errors[-5:])
        )
    finally:
        for path, content in backups.items():
            if content is None:
                try:
                    os.unlink(path)
                except FileNotFoundError:
                    pass
            else:
                with open(path, "wb") as f:
                    f.write(content)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
