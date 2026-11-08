#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import io
import json
import os
import random
import signal
import socket
import stat
import subprocess
import tempfile
import time
import urllib.request

import pytest

SUMMARY = "/home/user/daily_summary.json"
SCRIPT = "/home/user/process_pipeline.py"
CSV_PATH = "/home/user/transactions.csv"
RATES_PATH = "/home/user/exchange_rates.json"


def test_daily_summary_exists_and_correct():
    assert os.path.exists(SUMMARY), f"The output file {SUMMARY} does not exist."
    assert os.path.isfile(SUMMARY), f"The path {SUMMARY} is not a file."

    with open(SUMMARY, "r") as f:
        try:
            result = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {SUMMARY} is not valid JSON.")

    expected = {
        "2023-01-15": 155.0,
        "2023-01-16": 70.0,
        "2023-01-17": 187.5,
    }

    assert isinstance(result, dict), f"Expected the JSON root to be a dictionary, got {type(result).__name__}."
    assert set(result.keys()) == set(expected.keys()), f"Expected dates {set(expected.keys())}, got {set(result.keys())}."

    for date_key, expected_val in expected.items():
        actual_val = result[date_key]
        assert isinstance(actual_val, float), f"Expected value for {date_key} to be a float, got {type(actual_val).__name__}."
        assert round(actual_val, 2) == expected_val, f"Expected {expected_val} for {date_key}, got {actual_val}."


def _assigned_names(node):
    names = set()
    if isinstance(node, ast.Name):
        names.add(node.id)
    elif isinstance(node, (ast.Tuple, ast.List)):
        for item in node.elts:
            names.update(_assigned_names(item))
    return names


def _check_streaming_source(source):
    tree = ast.parse(source, filename=SCRIPT)
    request_vars = set()
    url_vars = set()
    requests_stream_call = False
    urllib_call = False

    for node in ast.walk(tree):
        value = None
        targets = []
        if isinstance(node, ast.Assign):
            value = node.value
            targets = node.targets
        elif isinstance(node, ast.AnnAssign):
            value = node.value
            targets = [node.target]
        elif isinstance(node, ast.NamedExpr):
            value = node.value
            targets = [node.target]

        if isinstance(value, ast.Call):
            fname = value.func.attr if isinstance(value.func, ast.Attribute) else (value.func.id if isinstance(value.func, ast.Name) else "")
            if fname in {"get", "request"} and any(
                kw.arg == "stream" and isinstance(kw.value, ast.Constant) and kw.value.value is True
                for kw in value.keywords
            ):
                requests_stream_call = True
                for target in targets:
                    request_vars.update(_assigned_names(target))
            if fname == "urlopen":
                urllib_call = True
                for target in targets:
                    url_vars.update(_assigned_names(target))

        if isinstance(node, ast.With):
            for item in node.items:
                call = item.context_expr
                if isinstance(call, ast.Call):
                    fname = call.func.attr if isinstance(call.func, ast.Attribute) else (call.func.id if isinstance(call.func, ast.Name) else "")
                    if fname == "urlopen":
                        urllib_call = True
                        if item.optional_vars:
                            url_vars.update(_assigned_names(item.optional_vars))

        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == "open" and node.args:
            arg = node.args[0]
            if isinstance(arg, ast.Constant) and isinstance(arg.value, str) and "transactions.csv" in arg.value:
                pytest.fail("process_pipeline.py opens transactions.csv locally instead of consuming it through HTTP")

    requests_stream_use = False
    urllib_stream_use = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Attribute) and isinstance(node.value, ast.Name):
            if node.value.id in request_vars:
                if node.attr in {"content", "text"}:
                    pytest.fail("The HTTP response is materialized in memory instead of streamed")
                if node.attr in {"iter_lines", "iter_content", "raw"}:
                    requests_stream_use = True
            if node.value.id in url_vars and node.attr == "readlines":
                pytest.fail("The HTTP response is loaded with readlines() instead of streamed")

        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and isinstance(node.func.value, ast.Name):
            if node.func.value.id in url_vars:
                if node.func.attr == "read" and not node.args and not node.keywords:
                    pytest.fail("The entire HTTP response is read into memory at once")
                if node.func.attr in {"read", "readline"} and (node.args or node.func.attr == "readline"):
                    urllib_stream_use = True

        if isinstance(node, ast.For) and isinstance(node.iter, ast.Name) and node.iter.id in url_vars:
            urllib_stream_use = True

        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id in {"TextIOWrapper", "iter"}:
            if any(isinstance(arg, ast.Name) and arg.id in url_vars for arg in node.args):
                urllib_stream_use = True

        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr in {"iterdecode", "TextIOWrapper"}:
            if any(isinstance(arg, ast.Name) and arg.id in url_vars for arg in node.args):
                urllib_stream_use = True

    assert (requests_stream_call and requests_stream_use) or (urllib_call and urllib_stream_use), (
        "process_pipeline.py must consume the HTTP response incrementally, such as with "
        "requests stream=True plus iter_lines/iter_content/raw, or by iterating a urlopen response"
    )


def _builtin_server_pids():
    found = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            raw = open(f"/proc/{entry}/cmdline", "rb").read()
            args = [part.decode(errors="ignore") for part in raw.split(b"\0") if part]
        except (OSError, PermissionError):
            continue
        if "http.server" in args and "8080" in args:
            found.append(int(entry))
    return found


def _wait_for_server(proc, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if proc.poll() is not None:
            return False
        try:
            with socket.create_connection(("127.0.0.1", 8080), timeout=0.2):
                return True
        except OSError:
            time.sleep(0.1)
    return False


def test_pipeline_artifact_http_streaming_and_dynamic_processing():
    assert os.path.exists(SCRIPT), f"The required script {SCRIPT} does not exist."
    assert os.path.isfile(SCRIPT), f"The path {SCRIPT} is not a regular file."
    source = open(SCRIPT, "r", encoding="utf-8").read()
    _check_streaming_source(source)

    existing_servers = _builtin_server_pids()
    assert existing_servers, "No background Python built-in http.server process is running on port 8080."
    try:
        with urllib.request.urlopen("http://localhost:8080/transactions.csv", timeout=5) as response:
            assert response.status == 200
            assert b"timestamp" in response.readline()
    except Exception as exc:
        pytest.fail(f"The required local HTTP service did not serve transactions.csv: {exc}")

    backups = {}
    for path in (CSV_PATH, RATES_PATH, SUMMARY):
        if os.path.exists(path):
            backups[path] = (open(path, "rb").read(), stat.S_IMODE(os.stat(path).st_mode))
        else:
            backups[path] = None

    server = None
    log_file = None
    try:
        for pid in existing_servers:
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        time.sleep(0.5)

        rng = random.SystemRandom()
        eur_rate = rng.choice([1.07, 1.13, 1.19, 1.31])
        gbp_rate = rng.choice([1.21, 1.27, 1.33, 1.39])
        usd_a = rng.randint(31, 97)
        eur_a = rng.randint(41, 109)
        gbp_a = rng.randint(23, 83)
        usd_b = rng.randint(17, 71)

        rates = {"USD": 1.0, "EUR": eur_rate, "GBP": gbp_rate, "JPY": 0.01}
        with open(RATES_PATH, "w") as f:
            json.dump(rates, f)
        os.chmod(RATES_PATH, 0o644)

        rows = [
            ["03/21/2027 14:30:00", " First@Example.COM ", str(usd_a), "USD"],
            ["2027-03-21T18:45:00Z", "second@test.org", str(eur_a), "EUR"],
            ["22-03-2027 09:15", "third@example.net", str(gbp_a), "GBP"],
            ["03/22/2027 11:00:00", "   ", "99999", "USD"],
            ["2027-03-22T22:10:00Z", "unknown@example.com", "777", "AUD"],
            ["03/23/2027 08:00:00", " fourth@example.com ", str(usd_b), "USD"],
        ]
        with open(CSV_PATH, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["timestamp", "email", "amount", "currency"])
            writer.writerows(rows)
        # The verifier's root-owned server can read this, but the submitted script,
        # run as user, cannot bypass HTTP by opening the file locally.
        os.chmod(CSV_PATH, 0o600)

        expected = {
            "2027-03-21": round(usd_a + eur_a * eur_rate, 2),
            "2027-03-22": round(gbp_a * gbp_rate, 2),
            "2027-03-23": round(float(usd_b), 2),
        }

        if os.path.exists(SUMMARY):
            os.unlink(SUMMARY)

        log_file = tempfile.NamedTemporaryFile(mode="w+b", delete=False)
        server = subprocess.Popen(
            ["python3", "-u", "-m", "http.server", "8080", "--bind", "127.0.0.1", "--directory", "/home/user"],
            stdout=log_file,
            stderr=log_file,
        )
        assert _wait_for_server(server), "Could not start the controlled built-in HTTP server on port 8080."

        completed = subprocess.run(
            ["runuser", "-u", "user", "--", "python3", SCRIPT],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert completed.returncode == 0, (
            f"process_pipeline.py failed on fresh input.\nstdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
        )
        assert os.path.isfile(SUMMARY), "Running process_pipeline.py did not create daily_summary.json."

        with open(SUMMARY, "r") as f:
            result = json.load(f)
        assert isinstance(result, dict), f"Expected the JSON root to be a dictionary, got {type(result).__name__}."
        assert set(result.keys()) == set(expected.keys()), f"Expected dates {set(expected.keys())}, got {set(result.keys())}."
        for date_key, expected_val in expected.items():
            actual_val = result[date_key]
            assert isinstance(actual_val, float), f"Expected value for {date_key} to be a float, got {type(actual_val).__name__}."
            assert round(actual_val, 2) == expected_val, f"Expected {expected_val} for {date_key}, got {actual_val}."

        server.terminate()
        server.wait(timeout=5)
        log_file.flush()
        log_file.seek(0)
        server_log = log_file.read().decode(errors="replace")
        assert '"GET /transactions.csv' in server_log and " 200 " in server_log, (
            "The executed pipeline did not fetch transactions.csv successfully through the HTTP server."
        )
    finally:
        if server is not None and server.poll() is None:
            server.kill()
            server.wait()
        if log_file is not None:
            name = log_file.name
            log_file.close()
            try:
                os.unlink(name)
            except OSError:
                pass
        for path, backup in backups.items():
            if backup is None:
                try:
                    os.unlink(path)
                except FileNotFoundError:
                    pass
            else:
                data, mode = backup
                with open(path, "wb") as f:
                    f.write(data)
                os.chmod(path, mode)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
