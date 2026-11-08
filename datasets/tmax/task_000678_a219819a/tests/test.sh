#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import socket
import string
import subprocess
import time

import pytest
import requests

PROJECT = "/app/etl-worker"
EXECUTABLE = os.path.join(PROJECT, "etl_server")
PRIMARY_URL = "http://127.0.0.1:8080/extract"


def post_with_retry(url, payload, retries=8):
    last_error = None
    for _ in range(retries):
        try:
            response = requests.post(url, data=payload, timeout=2)
            if response.status_code == 200:
                return response
            last_error = AssertionError(
                f"Expected status code 200 from {url}, got {response.status_code}"
            )
        except requests.exceptions.RequestException as exc:
            last_error = exc
        time.sleep(0.5)
    pytest.fail(f"Could not obtain a successful response from {url}: {last_error}")


def random_txn():
    letters = "".join(secrets.choice(string.ascii_uppercase) for _ in range(4))
    digits = "".join(secrets.choice(string.digits) for _ in range(5))
    return f"TXN-{letters}-{digits}"


@pytest.fixture(scope="session", autouse=True)
def rebuilt_server():
    dry_run = subprocess.run(
        ["make", "-B", "-n", "all"],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=30,
    )
    assert dry_run.returncode == 0, f"Makefile dry run failed:\n{dry_run.stdout}"
    link_lines = [
        line for line in dry_run.stdout.splitlines()
        if "etl_server" in line and ("-pthread" in line or "-lpthread" in line)
    ]
    assert link_lines, (
        "The Makefile's etl_server link command must include a threading linker "
        f"flag such as -pthread or -lpthread. Dry-run output:\n{dry_run.stdout}"
    )

    subprocess.run(["make", "clean"], cwd=PROJECT, stdout=subprocess.PIPE,
                   stderr=subprocess.STDOUT, text=True, timeout=30)
    for path in (EXECUTABLE,
                 os.path.join(PROJECT, "src", "main.o"),
                 os.path.join(PROJECT, "src", "extractor.o")):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    build = subprocess.run(
        ["make"], cwd=PROJECT, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=120
    )
    assert build.returncode == 0, f"The project did not build successfully with make:\n{build.stdout}"
    assert os.path.isfile(EXECUTABLE), "make did not produce /app/etl-worker/etl_server"
    assert os.access(EXECUTABLE, os.X_OK), "etl_server is not executable"
    with open(EXECUTABLE, "rb") as artifact:
        assert artifact.read(4) == b"\x7fELF", "etl_server is not a compiled ELF executable"

    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        alternate_port = sock.getsockname()[1]

    process = subprocess.Popen(
        [EXECUTABLE, "127.0.0.1", str(alternate_port)],
        cwd=PROJECT,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    alternate_url = f"http://127.0.0.1:{alternate_port}/extract"

    for _ in range(20):
        if process.poll() is not None:
            pytest.fail(f"Rebuilt etl_server exited early with status {process.returncode}")
        try:
            requests.post(alternate_url, data="readiness", timeout=0.5)
            break
        except requests.exceptions.RequestException:
            time.sleep(0.25)
    else:
        process.terminate()
        pytest.fail("The rebuilt etl_server did not listen on the configured host and port")

    yield alternate_url

    process.terminate()
    try:
        process.wait(timeout=3)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=3)


def parse_json_list(response):
    try:
        result = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    assert isinstance(result, list), "Expected the response to be a JSON array."
    assert all(isinstance(item, str) for item in result), "Every extracted ID must be a string"
    return result


def test_executable_exists():
    """Check if the compiled etl_server executable exists."""
    assert os.path.isfile('/app/etl-worker/etl_server'), "The executable '/app/etl-worker/etl_server' was not found. Did you compile the project?"


def test_etl_service_extraction():
    """Retain the original extraction check against the required running service."""
    payload = (
        "Error log start\n"
        "Details:\n"
        "TXN-ABCD-12345\n"
        "More text\n"
        "Another one: TXN-WXYZ-98765 \n"
        "Invalid ones: TXN-ABC-12345 TXN-ABCDE-12345 TXN-ABCD-1234\n"
        "TXN-ZZZZ-00000\n"
        "End of log."
    )
    expected_ids = ["TXN-ABCD-12345", "TXN-WXYZ-98765", "TXN-ZZZZ-00000"]
    response = post_with_retry(PRIMARY_URL, payload, retries=5)
    result = parse_json_list(response)
    assert sorted(result) == sorted(expected_ids), (
        f"Extracted IDs do not match expected. Got: {result}, Expected: {expected_ids}"
    )


def test_randomized_general_extraction(rebuilt_server):
    """Exercise both the required service and the freshly rebuilt artifact on unpredictable data."""
    for _ in range(4):
        ids = []
        while len(ids) < 5:
            candidate = random_txn()
            if candidate not in ids:
                ids.append(candidate)

        chunks = [
            f"header with noise\n{ids[0]}\nnext line",
            f"tab-separated:\t{ids[1]}\r\ncontinuation",
            f"punctuation ({ids[2]}) and more text",
            f"spaces   {ids[3]}   \n",
            f"final\n\n{ids[4]}\nend",
            "invalid: TXN-ABC-12345 TXN-ABCDE-12345 TXN-ABCD-1234 txn-ABCD-12345",
        ]
        random.SystemRandom().shuffle(chunks)
        payload = "\n---\n".join(chunks)

        for url in (PRIMARY_URL, rebuilt_server):
            result = parse_json_list(post_with_retry(url, payload))
            assert sorted(result) == sorted(ids), (
                f"Randomized extraction failed for {url}. Got {result}, expected {ids}"
            )


def test_no_matches_returns_empty_list(rebuilt_server):
    payload = "No transactions here.\nTXN-ABC-12345\nTXN-ABCDE-12345\nTXN-abcd-12345"
    for url in (PRIMARY_URL, rebuilt_server):
        result = parse_json_list(post_with_retry(url, payload))
        assert result == [], f"Expected no extracted IDs from {url}, got {result}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
