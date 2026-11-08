#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import re
import secrets
import statistics
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

import pytest

ENV_FILE = "/app/.env"
NGINX_CONF = "/app/nginx/nginx.conf"
VALIDATE_SCRIPT = "/home/user/validate_loc.py"
CLEAN_CORPUS_DIR = "/app/data/clean/"
EVIL_CORPUS_DIR = "/app/data/evil/"
INGEST_URL = "http://localhost:8080/ingest"


@pytest.fixture(scope="session", autouse=True)
def restart_services():
    """Start Redis, Flask, and Nginx with the configuration the task requires."""
    subprocess.run(["service", "nginx", "stop"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    subprocess.run(["pkill", "-f", "python3 /app/api.py"], check=False)

    redis_result = subprocess.run(
        ["service", "redis-server", "restart"], capture_output=True, text=True
    )
    assert redis_result.returncode == 0, redis_result.stdout + redis_result.stderr

    config_test = subprocess.run(
        ["nginx", "-t", "-c", NGINX_CONF], capture_output=True, text=True
    )
    assert config_test.returncode == 0, config_test.stdout + config_test.stderr

    nginx_start = subprocess.run(
        ["nginx", "-c", NGINX_CONF], capture_output=True, text=True
    )
    assert nginx_start.returncode == 0, nginx_start.stdout + nginx_start.stderr

    api_log = open("/tmp/verifier_api.log", "w")
    api_proc = subprocess.Popen(
        ["python3", "/app/api.py"], stdout=api_log, stderr=subprocess.STDOUT
    )

    ready = False
    for _ in range(50):
        if api_proc.poll() is not None:
            break
        try:
            urllib.request.urlopen(INGEST_URL, timeout=0.2)
        except urllib.error.HTTPError:
            ready = True
            break
        except urllib.error.URLError:
            time.sleep(0.1)
    assert ready, "The Nginx -> Flask endpoint did not become reachable"

    yield

    api_proc.terminate()
    try:
        api_proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        api_proc.kill()
    api_log.close()


def test_env_configuration():
    assert os.path.isfile(ENV_FILE), f"{ENV_FILE} is missing."
    with open(ENV_FILE, "r") as f:
        content = f.read()
    found = any(line.strip() == "REDIS_HOST=127.0.0.1" for line in content.splitlines())
    assert found, f"REDIS_HOST is not set to 127.0.0.1 in {ENV_FILE}"


def test_nginx_configuration():
    assert os.path.isfile(NGINX_CONF), f"{NGINX_CONF} is missing."
    with open(NGINX_CONF, "r") as f:
        content = f.read()

    assert "proxy_pass http://127.0.0.1:5000" in content or \
           "proxy_pass http://localhost:5000" in content, \
           f"Nginx configuration does not properly proxy to Flask in {NGINX_CONF}"

    uncommented = "\n".join(line.split("#", 1)[0] for line in content.splitlines())
    assert re.search(
        r"proxy_pass\s+http://(?:127\.0\.0\.1|localhost):5000(?:/ingest)?\s*;",
        uncommented,
    ), "The required proxy_pass is absent or commented out"


def test_validate_loc_script_exists():
    assert os.path.isfile(VALIDATE_SCRIPT), f"Validation script missing at {VALIDATE_SCRIPT}"


def parse_fixture(path):
    if path.lower().endswith(".json"):
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    if path.lower().endswith(".csv"):
        with open(path, newline="", encoding="utf-8") as f:
            return {row["key"]: row["translation"] for row in csv.DictReader(f)}
    raise AssertionError(f"Unexpected fixture format: {path}")


def should_reject(data):
    values = list(data.values())
    lengths = [len(value) for value in values]
    mean = statistics.mean(lengths) if lengths else 0
    std_dev = statistics.pstdev(lengths) if lengths else 0
    return any(
        len(value) > mean + 3 * std_dev or "<script>" in value or "${" in value
        for value in values
    )


def run_validator(input_path, output_path, expected, reject):
    if os.path.exists(output_path):
        os.unlink(output_path)
    result = subprocess.run(
        ["python3", VALIDATE_SCRIPT, input_path, output_path],
        capture_output=True, text=True, timeout=10
    )
    if reject:
        assert result.returncode == 1, (
            f"Expected rejection, got exit {result.returncode}: {result.stderr}"
        )
        assert not os.path.exists(output_path), "Rejected input wrote an output file"
    else:
        assert result.returncode == 0, (
            f"Expected acceptance, got exit {result.returncode}: {result.stderr}"
        )
        assert os.path.isfile(output_path), "Accepted input did not create output"
        with open(output_path, encoding="utf-8") as f:
            actual = json.load(f)
        assert actual == expected, "Output JSON does not exactly preserve parsed translations"


def test_validate_loc_corpus_direct():
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus missing at {CLEAN_CORPUS_DIR}"
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus missing at {EVIL_CORPUS_DIR}"

    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR)
                   if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR)
                  if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    assert clean_files, "No clean corpus files found."
    assert evil_files, "No evil corpus files found."

    with tempfile.TemporaryDirectory() as tmpdir:
        for path in clean_files + evil_files:
            expected = parse_fixture(path)
            run_validator(
                path,
                os.path.join(tmpdir, secrets.token_hex(8) + ".json"),
                expected,
                should_reject(expected),
            )


def write_json(path, data):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f)


def write_csv(path, data):
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=["key", "translation"])
        writer.writeheader()
        for key, value in data.items():
            writer.writerow({"key": key, "translation": value})


def generated_cases(tmpdir):
    token = secrets.token_hex(12)
    cases = []

    clean_json = {
        "hello_" + token: "translated " + token,
        "other_" + token: "another translation " + token,
        "short_" + token: "ordinary text " + token,
    }
    path = os.path.join(tmpdir, "random_clean.json")
    write_json(path, clean_json)
    cases.append((path, clean_json, False))

    clean_csv = {
        "csv_a_" + token: "text, with a comma " + token,
        "csv_b_" + token: "quoted ordinary translation " + token,
        "csv_c_" + token: "more ordinary content " + token,
    }
    path = os.path.join(tmpdir, "random_clean.csv")
    write_csv(path, clean_csv)
    cases.append((path, clean_csv, False))

    # With only two lengths, even a very large difference is not beyond 3 sigma.
    two_values = {"small_" + token: "x", "large_" + token: "y" * 1000}
    path = os.path.join(tmpdir, "two_values.csv")
    write_csv(path, two_values)
    cases.append((path, two_values, False))

    anomalous = {f"normal_{i}_{token}": "n" * 10 for i in range(30)}
    anomalous["outlier_" + token] = "z" * 500
    path = os.path.join(tmpdir, "statistical_outlier.json")
    write_json(path, anomalous)
    cases.append((path, anomalous, True))

    script_bad = {"safe_" + token: "ordinary", "bad_" + token: "xx<script>yy"}
    path = os.path.join(tmpdir, "script_bad.csv")
    write_csv(path, script_bad)
    cases.append((path, script_bad, True))

    interpolation_bad = {"safe_" + token: "ordinary", "bad_" + token: "prefix ${name}"}
    path = os.path.join(tmpdir, "interpolation_bad.json")
    write_json(path, interpolation_bad)
    cases.append((path, interpolation_bad, True))
    return cases


def test_generated_direct_behavior_and_exact_outputs():
    with tempfile.TemporaryDirectory() as tmpdir:
        for index, (path, expected, reject) in enumerate(generated_cases(tmpdir)):
            run_validator(path, os.path.join(tmpdir, f"output_{index}.json"),
                          expected, reject)


def post_multipart_file(url, file_path):
    boundary = secrets.token_hex(16)
    filename = os.path.basename(file_path)
    with open(file_path, "rb") as f:
        file_content = f.read()
    body = (
        f"--{boundary}\r\n"
        f"Content-Disposition: form-data; name=\"file\"; filename=\"{filename}\"\r\n"
        f"Content-Type: application/octet-stream\r\n\r\n"
    ).encode() + file_content + f"\r\n--{boundary}--\r\n".encode()
    req = urllib.request.Request(url, data=body)
    req.add_header("Content-Type", f"multipart/form-data; boundary={boundary}")
    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            return response.status
    except urllib.error.HTTPError as e:
        return e.code
    except urllib.error.URLError:
        return None


def test_http_endpoint_corpus():
    files = []
    for directory in (CLEAN_CORPUS_DIR, EVIL_CORPUS_DIR):
        files.extend(os.path.join(directory, name) for name in os.listdir(directory)
                     if os.path.isfile(os.path.join(directory, name)))
    assert files
    for path in files:
        expected = parse_fixture(path)
        wanted = 400 if should_reject(expected) else 200
        assert post_multipart_file(INGEST_URL, path) == wanted


def test_http_endpoint_generated_cases():
    with tempfile.TemporaryDirectory() as tmpdir:
        for path, expected, reject in generated_cases(tmpdir):
            wanted = 400 if reject else 200
            status = post_multipart_file(INGEST_URL, path)
            assert status == wanted, f"{os.path.basename(path)} returned {status}, wanted {wanted}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
