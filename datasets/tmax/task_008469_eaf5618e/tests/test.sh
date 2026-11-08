#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import http.client
import json
import os
import secrets
import socket
import stat
import subprocess
import time

MIGRATOR = "/home/user/schema_migrator.py"
E2E = "/home/user/run_e2e.sh"
LEGACY = "/home/user/legacy_data.json"
RESPONSE = "/home/user/migrated_response.json"


def test_schema_migrator_exists():
    assert os.path.exists(MIGRATOR), f"File {MIGRATOR} does not exist."
    assert os.path.isfile(MIGRATOR), f"Path {MIGRATOR} is not a file."


def test_run_e2e_script_exists_and_executable():
    assert os.path.exists(E2E), f"File {E2E} does not exist."
    assert os.path.isfile(E2E), f"Path {E2E} is not a file."
    st = os.stat(E2E)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {E2E} is not executable."


def test_migrated_response_correct():
    assert os.path.exists(RESPONSE), f"File {RESPONSE} does not exist. Did the e2e script run successfully?"
    with open(RESPONSE, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {RESPONSE} does not contain valid JSON."

    expected_data = [
        {"first_name": "Alice", "last_name": "Walker", "age": 34, "identifier": 1},
        {"first_name": "Bob", "last_name": "Martin Lee", "age": 39, "identifier": 2},
    ]
    assert isinstance(data, list), "Migrated data should be a JSON array (list)."
    assert len(data) == len(expected_data), f"Expected {len(expected_data)} items, got {len(data)}."
    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert actual.get("first_name") == expected["first_name"], f"Item {i}: expected first_name '{expected['first_name']}', got '{actual.get('first_name')}'"
        assert actual.get("last_name") == expected["last_name"], f"Item {i}: expected last_name '{expected['last_name']}', got '{actual.get('last_name')}'"
        assert actual.get("age") == expected["age"], f"Item {i}: expected age {expected['age']}, got {actual.get('age')}"
        assert actual.get("identifier") == expected["identifier"], f"Item {i}: expected identifier {expected['identifier']}, got {actual.get('identifier')}"


def expected_for(records):
    result = []
    for record in records:
        first, separator, remainder = record["full_name"].partition(" ")
        result.append({
            "first_name": first,
            "last_name": remainder if separator else "",
            "age": 2024 - int(record["birth_year"]),
            "identifier": int(record["id"]),
        })
    return result


def assert_exact_payload(payload, expected):
    assert payload == expected, f"Expected migrated payload {expected!r}, got {payload!r}"
    for item in payload:
        assert type(item["first_name"]) is str
        assert type(item["last_name"]) is str
        assert type(item["age"]) is int
        assert type(item["identifier"]) is int


def server_is_reachable():
    try:
        with socket.create_connection(("127.0.0.1", 8080), timeout=0.25):
            return True
    except OSError:
        return False


def test_dynamic_e2e_and_http_server():
    with open(LEGACY, "rb") as f:
        original_legacy = f.read()
    with open(RESPONSE, "rb") as f:
        original_response = f.read()

    token = secrets.token_hex(5)
    records = [
        {"full_name": f"Nova{token} van Buren", "birth_year": "1977", "id": "41027"},
        {"full_name": f"Orion{token} Delta Echo", "birth_year": "2003", "id": "58319"},
        {"full_name": f"Pia{token} Sol", "birth_year": "1964", "id": "72641"},
    ]
    expected = expected_for(records)
    server_process = None

    try:
        with open(LEGACY, "w") as f:
            json.dump(records, f)
        with open(RESPONSE, "w") as f:
            f.write("verifier sentinel: run_e2e.sh did not replace this")

        assert not server_is_reachable(), "Port 8080 was already serving before run_e2e.sh was invoked."
        completed = subprocess.run(
            [E2E], cwd="/home/user", text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15
        )
        assert completed.returncode == 0, (
            f"run_e2e.sh failed with exit code {completed.returncode}.\n"
            f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
        )
        with open(RESPONSE, "r") as f:
            e2e_payload = json.load(f)
        assert_exact_payload(e2e_payload, expected)

        deadline = time.time() + 3
        while time.time() < deadline and server_is_reachable():
            time.sleep(0.1)
        assert not server_is_reachable(), "run_e2e.sh did not stop its background HTTP server."

        token2 = secrets.token_hex(5)
        direct_records = [
            {"full_name": f"Quinn{token2} North West", "birth_year": "1996", "id": "86420"},
            {"full_name": f"Rhea{token2} Stone", "birth_year": "1981", "id": "97531"},
        ]
        direct_expected = expected_for(direct_records)
        with open(LEGACY, "w") as f:
            json.dump(direct_records, f)

        server_process = subprocess.Popen(
            ["python3", MIGRATOR], cwd="/home/user",
            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True
        )

        deadline = time.time() + 8
        last_error = None
        response = None
        body = None
        while time.time() < deadline:
            if server_process.poll() is not None:
                stderr = server_process.stderr.read()
                raise AssertionError(f"schema_migrator.py exited before serving HTTP: {stderr}")
            try:
                connection = http.client.HTTPConnection("127.0.0.1", 8080, timeout=1)
                connection.request("GET", "/api/v2/users")
                response = connection.getresponse()
                body = response.read()
                break
            except OSError as exc:
                last_error = exc
                time.sleep(0.1)
            finally:
                try:
                    connection.close()
                except Exception:
                    pass

        assert response is not None, f"Server did not listen on port 8080: {last_error}"
        assert response.status == 200, f"GET /api/v2/users returned HTTP {response.status}"
        content_type = response.getheader("Content-Type")
        assert content_type is not None, "GET /api/v2/users did not include Content-Type."
        assert content_type.split(";", 1)[0].strip().lower() == "application/json", (
            f"Expected Content-Type application/json, got {content_type!r}"
        )
        try:
            direct_payload = json.loads(body.decode("utf-8"))
        except Exception as exc:
            raise AssertionError(f"HTTP response was not valid UTF-8 JSON: {exc}")
        assert_exact_payload(direct_payload, direct_expected)
    finally:
        if server_process is not None and server_process.poll() is None:
            server_process.terminate()
            try:
                server_process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                server_process.kill()
                server_process.wait(timeout=3)
        with open(LEGACY, "wb") as f:
            f.write(original_legacy)
        with open(RESPONSE, "wb") as f:
            f.write(original_response)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
