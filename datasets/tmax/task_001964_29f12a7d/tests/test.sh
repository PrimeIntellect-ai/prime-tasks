#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import random
import re
import secrets
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import pytest
import requests

MAKEFILE = "/app/vendored_data_parser/Makefile"
VALIDATOR = "/home/user/schema_validator.py"
PROPERTY_TEST = "/home/user/test_schema_validator.py"
RESULT_LOG = "/home/user/test_results.log"
PID_FILE = "/home/user/service.pid"
URL = "http://127.0.0.1:8080/validate"
TOKEN = {"Authorization": "Bearer release-manager-token-992"}


def run(cmd, **kwargs):
    return subprocess.run(cmd, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, **kwargs)


def test_makefile_fixed():
    path = MAKEFILE
    assert os.path.isfile(path), f"File {path} does not exist."
    content = Path(path).read_text()
    assert "-ldata_lib_v2" in content, "Makefile does not contain the correct linker flag '-ldata_lib_v2'."
    assert "-lold_data_lib_v1" not in content, "Makefile still contains the old linker flag '-lold_data_lib_v1'."

    clean = run(["make", "clean"], cwd="/app/vendored_data_parser", timeout=30)
    assert clean.returncode == 0, clean.stdout
    build = run(["make", "all"], cwd="/app/vendored_data_parser", timeout=60)
    assert build.returncode == 0, build.stdout
    so = Path("/app/vendored_data_parser/data_parser.so")
    assert so.is_file(), "The build did not produce data_parser.so"
    assert so.read_bytes()[:4] == b"\x7fELF", "data_parser.so is not an ELF shared object"

    probe = run([
        sys.executable, "-c",
        "import vendored_data_parser as v; "
        "assert v.parse_hex('a1B2') == 'valid_parser_output_a1B2'; "
        "print(v.__file__)"
    ], env={**os.environ, "PYTHONPATH": "/app"}, timeout=20)
    assert probe.returncode == 0, probe.stdout


def test_schema_validator_exists():
    path = VALIDATOR
    assert os.path.isfile(path), f"File {path} does not exist."


def test_schema_validator_semantics_and_import():
    rng = random.Random(secrets.randbits(64))
    cases = []

    # Random valid SemVer values. Compatibility follows the stated core-version
    # rule; prerelease identifiers are valid SemVer and build metadata is ignored.
    for _ in range(45):
        req_major = rng.randint(0, 8)
        req_minor = rng.randint(0, 20)
        req_patch = rng.randint(0, 30)
        avail_major = rng.randint(0, 8)
        avail_minor = rng.randint(0, 20)
        avail_patch = rng.randint(0, 30)
        req = f"{req_major}.{req_minor}.{req_patch}"
        avail = f"{avail_major}.{avail_minor}.{avail_patch}"
        if rng.choice([True, False]):
            req += "-alpha." + str(rng.randint(0, 9))
        if rng.choice([True, False]):
            req += "+build." + str(rng.randint(0, 999))
        if rng.choice([True, False]):
            avail += "+meta." + str(rng.randint(0, 999))
        expected = (req_major == avail_major and
                    (avail_minor > req_minor or
                     (avail_minor == req_minor and avail_patch >= req_patch)))
        cases.append([req, avail, expected])

    cases.extend([
        ["2.4.1-alpha.1", "2.4.1", True],
        ["2.4.1+build.7", "2.4.1+other", True],
        ["2.3.999", "2.4.0", True],
        ["2.4.2", "2.4.1", False],
        ["1.99.99", "2.4.1", False],
    ])
    invalid = [
        "", "1", "1.2", "1.2.3.4", "01.2.3", "1.02.3", "1.2.03",
        "v1.2.3", "1.2.-1", "1.2.3-", "1.2.3+", "1.2.3-alpha..1",
        "1.2.3-alpha_1", " 1.2.3", "1.2.3 ", "1.2.3+bad metadata"
    ]
    for bad in invalid:
        cases.append([bad, "2.4.1", False])
        cases.append(["2.4.0", bad, False])

    code = r'''
import json, sys
sys.path.insert(0, "/app")
sys.path.insert(0, "/home/user")
import schema_validator
assert "vendored_data_parser" in sys.modules, "schema_validator did not import vendored_data_parser"
assert callable(getattr(schema_validator, "is_compatible", None))
for requested, available, expected in json.loads(sys.stdin.read()):
    try:
        actual = schema_validator.is_compatible(requested, available)
    except Exception as exc:
        raise AssertionError(f"is_compatible raised for {requested!r}, {available!r}: {exc}")
    assert type(actual) is bool, f"non-bool result for {requested!r}, {available!r}: {actual!r}"
    assert actual is expected, f"wrong result for {requested!r}, {available!r}: {actual!r}, expected {expected!r}"
'''
    proc = subprocess.run([sys.executable, "-c", code], input=json.dumps(cases),
                          text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          env={**os.environ, "PYTHONPATH": "/home/user:/app"}, timeout=30)
    assert proc.returncode == 0, proc.stdout


def test_test_schema_validator_exists():
    path = PROPERTY_TEST
    assert os.path.isfile(path), f"File {path} does not exist."


def test_test_results_log_exists():
    path = RESULT_LOG
    assert os.path.isfile(path), f"File {path} does not exist."


def test_property_suite_and_log():
    source = Path(PROPERTY_TEST).read_text()
    tree = ast.parse(source, PROPERTY_TEST)
    imports_hypothesis = any(
        (isinstance(n, ast.Import) and any(a.name == "hypothesis" or a.name.startswith("hypothesis.") for a in n.names)) or
        (isinstance(n, ast.ImportFrom) and n.module and (n.module == "hypothesis" or n.module.startswith("hypothesis.")))
        for n in ast.walk(tree)
    )
    uses_given = any(
        isinstance(n, ast.Call) and
        ((isinstance(n.func, ast.Name) and n.func.id == "given") or
         (isinstance(n.func, ast.Attribute) and n.func.attr == "given"))
        for n in ast.walk(tree)
    )
    assert imports_hypothesis and uses_given, "The property test must actually use Hypothesis @given"

    saved_log = Path(RESULT_LOG).read_text(errors="replace")
    assert saved_log.strip(), "test_results.log is empty"
    assert re.search(r"\bpassed\b", saved_log, re.I), "test_results.log does not record a passing test run"

    actual = run([sys.executable, "-m", "pytest", "-q", PROPERTY_TEST],
                 cwd="/home/user", env={**os.environ, "PYTHONPATH": "/home/user:/app"}, timeout=90)
    assert actual.returncode == 0, actual.stdout
    assert re.search(r"\b[1-9][0-9]* passed\b", actual.stdout), "No property tests were collected and passed"

    # Mutation check: a validator that always accepts must be rejected, and the
    # generated tests must actually exercise an available lower major version.
    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        shutil.copy2(PROPERTY_TEST, td / "test_schema_validator.py")
        calls = td / "calls.jsonl"
        conftest = f'''
import json, sys, types
m = types.ModuleType("schema_validator")
def is_compatible(requested_version, available_version):
    with open({str(calls)!r}, "a") as f:
        f.write(json.dumps([requested_version, available_version]) + "\\n")
    return True
m.is_compatible = is_compatible
sys.modules["schema_validator"] = m
'''
        (td / "conftest.py").write_text(conftest)
        mutant = run([sys.executable, "-m", "pytest", "-q", str(td / "test_schema_validator.py")],
                     cwd=str(td), env={**os.environ, "PYTHONPATH": f"{td}:/app"}, timeout=90)
        assert mutant.returncode != 0, "Property tests accept a validator that always returns True"
        assert calls.exists(), "Property tests never called is_compatible"
        saw_lower_major = False
        for line in calls.read_text().splitlines():
            requested, available = json.loads(line)
            try:
                rm = int(str(requested).split(".", 1)[0])
                am = int(str(available).split(".", 1)[0])
            except (ValueError, IndexError):
                continue
            if am < rm:
                saw_lower_major = True
                break
        assert saw_lower_major, "Hypothesis tests did not exercise an available version with a lower major"


def _pid_and_listener_inode():
    assert os.path.isfile(PID_FILE), f"File {PID_FILE} does not exist."
    content = Path(PID_FILE).read_text().strip()
    assert content.isdigit(), f"PID file {PID_FILE} does not contain a valid integer PID."
    pid = int(content)
    assert Path(f"/proc/{pid}").is_dir(), f"PID {pid} is not running"

    listener_inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        if not os.path.exists(table):
            continue
        for line in Path(table).read_text().splitlines()[1:]:
            fields = line.split()
            if len(fields) >= 10 and fields[3] == "0A":
                try:
                    port = int(fields[1].rsplit(":", 1)[1], 16)
                except ValueError:
                    continue
                if port == 8080:
                    listener_inodes.add(fields[9])
    owned = set()
    for fd in Path(f"/proc/{pid}/fd").iterdir():
        try:
            target = os.readlink(fd)
        except OSError:
            continue
        match = re.fullmatch(r"socket:\[(\d+)\]", target)
        if match:
            owned.add(match.group(1))
    assert listener_inodes & owned, f"PID {pid} does not own the listening socket on port 8080"
    return pid


def test_service_pid_exists():
    pid = _pid_and_listener_inode()
    maps = Path(f"/proc/{pid}/maps").read_text(errors="replace")
    assert "/app/vendored_data_parser/data_parser.so" in maps, \
        "The service process has not loaded the vendored C extension"


def post(payload, headers=None):
    try:
        return requests.post(URL, json=payload, headers=headers or {}, timeout=3)
    except requests.RequestException as exc:
        pytest.fail(f"Failed to connect to service: {exc}")


def test_http_service_no_token():
    response = post({"data": "deadbeef", "schema_version": "2.4.0"})
    assert response.status_code == 401, f"Expected 401 Unauthorized, got {response.status_code}"


def test_http_service_bad_token():
    response = post({"data": "deadbeef", "schema_version": "2.4.0"},
                    {"Authorization": "Bearer bad-token"})
    assert response.status_code == 401, f"Expected 401 Unauthorized, got {response.status_code}"


def test_http_service_incompatible_version():
    response = post({"data": "deadbeef", "schema_version": "3.0.0"}, TOKEN)
    assert response.status_code == 400, f"Expected 400 Bad Request, got {response.status_code}"


def test_http_service_success():
    response = post({"data": "deadbeef", "schema_version": "2.4.0"}, TOKEN)
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail("Response is not valid JSON")
    assert data.get("status") == "success", f"Expected status 'success', got {data.get('status')}"
    assert data.get("parsed") == "valid_parser_output_deadbeef", \
        f"Expected parsed data 'valid_parser_output_deadbeef', got {data.get('parsed')}"


def test_http_service_dynamic_versions_and_parser_results():
    sys.path.insert(0, "/app")
    import vendored_data_parser

    rng = random.Random(secrets.randbits(64))
    requests_to_make = []
    for _ in range(18):
        raw = secrets.token_hex(rng.randint(1, 24))
        choice = rng.randrange(5)
        if choice == 0:
            version, compatible = f"2.{rng.randint(0, 3)}.{rng.randint(0, 999)}", True
        elif choice == 1:
            patch = rng.randint(0, 1)
            version, compatible = f"2.4.{patch}", True
        elif choice == 2:
            version, compatible = f"2.4.{rng.randint(2, 999)}", False
        elif choice == 3:
            version, compatible = f"2.{rng.randint(5, 30)}.{rng.randint(0, 999)}", False
        else:
            major = rng.choice([0, 1, 3, 4, 7])
            version, compatible = f"{major}.{rng.randint(0, 30)}.{rng.randint(0, 999)}", False
        requests_to_make.append((raw, version, compatible))

    for raw, version, compatible in requests_to_make:
        response = post({"data": raw, "schema_version": version}, TOKEN)
        if not compatible:
            assert response.status_code == 400, (raw, version, response.status_code, response.text)
            continue
        assert response.status_code == 200, (raw, version, response.status_code, response.text)
        body = response.json()
        expected = vendored_data_parser.parse_hex(raw)
        assert body.get("status") == "success"
        assert body.get("parsed") == expected, (raw, body, expected)

    for bad_version in ["2.4", "02.4.0", "2.04.0", "2.4.01", "v2.4.0", "2.4.0.0", "junk"]:
        response = post({"data": secrets.token_hex(5), "schema_version": bad_version}, TOKEN)
        assert response.status_code == 400, (bad_version, response.status_code, response.text)

    # The exact token is required, not merely a Bearer-shaped header.
    raw = secrets.token_hex(8)
    for bad_header in [
        {"Authorization": "release-manager-token-992"},
        {"Authorization": "bearer release-manager-token-992"},
        {"Authorization": "Bearer release-manager-token-992-extra"},
    ]:
        response = post({"data": raw, "schema_version": "2.4.0"}, bad_header)
        assert response.status_code == 401, (bad_header, response.status_code)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
