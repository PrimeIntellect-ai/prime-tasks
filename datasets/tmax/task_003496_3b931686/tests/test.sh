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
import os
import random
import re
import sqlite3
import stat
import string
import subprocess

import pytest
import requests


def test_api_job_a100():
    url = "http://127.0.0.1:8080/?job=A100"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to API or retrieve data for job A100: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"

    content_type = response.headers.get("Content-Type", "")
    assert "application/json" in content_type.lower(), f"Expected Content-Type application/json, got {content_type}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response body is not valid JSON: {response.text}")

    expected_data = {
        "job_id": "A100",
        "hostname": "db-prod-eu",
        "expected_gb": 500,
        "actual_gb": 490,
        "status": "SUCCESS"
    }

    assert data == expected_data, f"Expected JSON response {expected_data}, got {data}"


def test_api_job_b200():
    url = "http://127.0.0.1:8080/?job=B200"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to API or retrieve data for job B200: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"

    content_type = response.headers.get("Content-Type", "")
    assert "application/json" in content_type.lower(), f"Expected Content-Type application/json, got {content_type}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response body is not valid JSON: {response.text}")

    expected_data = {
        "job_id": "B200",
        "hostname": "db-prod-us",
        "expected_gb": 850,
        "actual_gb": 845,
        "status": "SUCCESS"
    }

    assert data == expected_data, f"Expected JSON response {expected_data}, got {data}"


def test_query_pipeline_and_api_wiring():
    script_path = "/home/user/query.sh"
    assert os.path.isfile(script_path), f"Required Bash script does not exist: {script_path}"

    with open(script_path, "rb") as f:
        original_script = f.read()
    original_mode = stat.S_IMODE(os.stat(script_path).st_mode)

    syntax = subprocess.run(
        ["/bin/bash", "-n", script_path],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )
    assert syntax.returncode == 0, f"query.sh is not valid Bash: {syntax.stderr}"

    alphabet = string.ascii_uppercase + string.digits
    while True:
        job_id = "V" + "".join(random.choice(alphabet) for _ in range(3))
        with sqlite3.connect("/app/inventory.db") as con:
            if con.execute("SELECT 1 FROM jobs WHERE id = ?", (job_id,)).fetchone() is None:
                break

    token = "".join(random.choice(string.ascii_lowercase + string.digits) for _ in range(10))
    server_id = "verifier-" + token
    hostname = "probe-" + token
    expected_gb = random.randint(1100, 9000)
    actual_gb = expected_gb - random.randint(1, 50)
    status_value = "VERIFY_" + token.upper()

    dump_path = "/app/nosql_dump.jsonl"
    with open(dump_path, "rb") as f:
        original_dump = f.read()

    marker = "/tmp/query-invoked-" + token
    try:
        with sqlite3.connect("/app/inventory.db") as con:
            con.execute("INSERT INTO servers(id, hostname) VALUES (?, ?)", (server_id, hostname))
            con.execute(
                "INSERT INTO jobs(id, server_id, expected_gb) VALUES (?, ?, ?)",
                (job_id, server_id, expected_gb),
            )
            con.commit()

        record = {
            "job_id": job_id,
            "metrics": {"actual_gb": actual_gb},
            "status": status_value,
        }
        with open(dump_path, "ab") as f:
            if original_dump and not original_dump.endswith(b"\n"):
                f.write(b"\n")
            f.write((json.dumps(record) + "\n").encode())

        # Derive the expected answer independently from the two live data sources.
        with sqlite3.connect("/app/inventory.db") as con:
            row = con.execute(
                "SELECT j.id, s.hostname, j.expected_gb "
                "FROM jobs AS j JOIN servers AS s ON j.server_id = s.id "
                "WHERE j.id = ?",
                (job_id,),
            ).fetchone()
        assert row is not None

        nosql_record = None
        with open(dump_path, encoding="utf-8") as f:
            for line in f:
                candidate = json.loads(line)
                if candidate.get("job_id") == job_id:
                    nosql_record = candidate
        assert nosql_record is not None

        expected = {
            "job_id": row[0],
            "hostname": row[1],
            "expected_gb": row[2],
            "actual_gb": nosql_record["metrics"]["actual_gb"],
            "status": nosql_record["status"],
        }

        traced = subprocess.run(
            ["/bin/bash", "-x", script_path, job_id],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        assert traced.returncode == 0, f"query.sh failed for a live job: {traced.stderr}"
        try:
            query_data = json.loads(traced.stdout)
        except ValueError:
            pytest.fail(f"query.sh did not emit a single valid JSON object: {traced.stdout!r}")
        assert query_data == expected, f"query.sh returned {query_data}, expected {expected}"

        trace = traced.stderr
        source = original_script.decode("utf-8", errors="replace")
        assert re.search(r"(?m)^\++\s+(?:\S*/)?sqlite3(?:\s|$)", trace), \
            "query.sh did not execute sqlite3"
        assert re.search(r"(?m)^\++\s+(?:\S*/)?jq(?:\s|$)", trace), \
            "query.sh did not execute jq"
        assert re.search(r"\bJOIN\b", source, re.IGNORECASE) or re.search(r"\bJOIN\b", trace, re.IGNORECASE), \
            "query.sh does not perform the required SQL JOIN"

        # Temporarily replace the script output with a unique probe. The API must
        # execute this path for the request and return its JSON verbatim.
        sentinel = {
            "job_id": job_id,
            "hostname": "api-wiring-" + token,
            "expected_gb": expected_gb + 101,
            "actual_gb": actual_gb + 202,
            "status": "PIPELINE_PROBE",
        }
        instrumented = (
            "#!/bin/bash\n"
            + "printf '' > " + marker + "\n"
            + "printf '%s\\n' '" + json.dumps(sentinel, separators=(",", ":")) + "'\n"
        ).encode()
        with open(script_path, "wb") as f:
            f.write(instrumented)
        os.chmod(script_path, original_mode | stat.S_IXUSR)

        try:
            response = requests.get(
                "http://127.0.0.1:8080/", params={"job": job_id}, timeout=5
            )
        except requests.exceptions.RequestException as e:
            pytest.fail(f"Failed to query API with dynamic job {job_id}: {e}")

        assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
        content_type = response.headers.get("Content-Type", "")
        assert "application/json" in content_type.lower(), \
            f"Expected Content-Type application/json, got {content_type}"
        assert os.path.exists(marker), "API did not execute /home/user/query.sh for the request"
        try:
            api_data = response.json()
        except ValueError:
            pytest.fail(f"API response is not valid JSON: {response.text}")
        assert api_data == sentinel, \
            f"API did not return the Bash script's output: expected {sentinel}, got {api_data}"
    finally:
        with open(script_path, "wb") as f:
            f.write(original_script)
        os.chmod(script_path, original_mode)
        with open(dump_path, "wb") as f:
            f.write(original_dump)
        with sqlite3.connect("/app/inventory.db") as con:
            con.execute("DELETE FROM jobs WHERE id = ?", (job_id,))
            con.execute("DELETE FROM servers WHERE id = ?", (server_id,))
            con.commit()
        try:
            os.unlink(marker)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
