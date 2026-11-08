#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import glob
import json
import os
import re
import secrets
import shutil
import stat
import subprocess

import pytest

PROJECT_DIR = "/home/user/router_project"


def test_makefile_fixed():
    makefile_path = os.path.join(PROJECT_DIR, "Makefile")
    assert os.path.isfile(makefile_path), f"Makefile is missing at {makefile_path}."

    with open(makefile_path, "r") as f:
        lines = f.readlines()

    # Preserve the original assertion.
    has_tab_gcc = any(line.startswith("\t") and "gcc" in line for line in lines)
    assert has_tab_gcc, "Makefile was not fixed to use tabs for the gcc build command."

    # Verify that the Makefile really builds the requested native executable.
    exe_path = os.path.join(PROJECT_DIR, "url_router")
    if os.path.lexists(exe_path):
        os.remove(exe_path)
    result = subprocess.run(
        ["make", "-B", "url_router"], cwd=PROJECT_DIR,
        capture_output=True, text=True, timeout=15
    )
    assert result.returncode == 0, (
        f"Makefile failed to build url_router.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(exe_path), "make did not create url_router."
    assert os.access(exe_path, os.X_OK), "The built url_router is not executable."
    with open(exe_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "url_router is not a compiled native executable."


def test_executable_built():
    exe_path = os.path.join(PROJECT_DIR, "url_router")
    assert os.path.isfile(exe_path), f"url_router executable was not found at {exe_path}."
    assert os.access(exe_path, os.X_OK), f"url_router at {exe_path} is not executable."


def test_report_json_exists_and_valid():
    report_path = os.path.join(PROJECT_DIR, "report.json")
    assert os.path.isfile(report_path), f"report.json was not generated at {report_path}."

    with open(report_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("report.json does not contain valid JSON.")

    assert "total_tested" in data, "Missing 'total_tested' key in report.json."
    assert "successful_executions" in data, "Missing 'successful_executions' key in report.json."
    assert "results" in data, "Missing 'results' key in report.json."

    assert data["total_tested"] == 4, f"Expected total_tested to be 4, got {data['total_tested']}."
    assert data["successful_executions"] == 4, f"Expected successful_executions to be 4, got {data['successful_executions']}."

    results = data["results"]
    assert isinstance(results, list), "'results' must be a list."
    assert len(results) == 4, f"Expected 4 results in the list, got {len(results)}."

    expected_results = [
        {"original_url": "/api/v1/users?id=10&active=true", "parsed_route": "/api/v1/users", "parsed_params": "id=10&active=true"},
        {"original_url": "/api/v1/status", "parsed_route": "/api/v1/status", "parsed_params": "none"},
        {"original_url": "/home?user=admin", "parsed_route": "/home", "parsed_params": "user=admin"},
        {"original_url": "/about", "parsed_route": "/about", "parsed_params": "none"}
    ]

    for i, expected in enumerate(expected_results):
        actual = results[i]
        assert actual.get("original_url") == expected["original_url"], f"Result {i} original_url mismatch. Expected '{expected['original_url']}', got '{actual.get('original_url')}'."
        assert actual.get("parsed_route") == expected["parsed_route"], f"Result {i} parsed_route mismatch. Expected '{expected['parsed_route']}', got '{actual.get('parsed_route')}'."
        assert actual.get("parsed_params") == expected["parsed_params"], f"Result {i} parsed_params mismatch. Expected '{expected['parsed_params']}', got '{actual.get('parsed_params')}'."


def test_router_c_fixed_behavior():
    exe_path = os.path.join(PROJECT_DIR, "url_router")
    if not os.path.isfile(exe_path):
        pytest.skip("url_router executable is missing, cannot test behavior.")

    # Preserve the original regression check.
    try:
        result = subprocess.run([exe_path, "/api/v1/status"], capture_output=True, text=True, timeout=2)
    except subprocess.TimeoutExpired:
        pytest.fail("url_router execution timed out.")

    assert result.returncode == 0, f"url_router crashed or returned non-zero exit code on URL without query params (returncode: {result.returncode})."
    expected_output = "ROUTE:/api/v1/status|PARAMS:none|VALID:1"
    assert expected_output in result.stdout, f"url_router output is incorrect for URL without query params. Expected to find '{expected_output}', got '{result.stdout.strip()}'."

    # Exercise both routing branches on verifier-generated inputs.
    token = secrets.token_hex(6)
    cases = [
        (f"/generated/{token}/status", f"ROUTE:/generated/{token}/status|PARAMS:none|VALID:1"),
        (f"/generated/{token}/items?id=37&sort=desc", f"ROUTE:/generated/{token}/items|PARAMS:id=37&sort=desc|VALID:1"),
        (f"/x-{token}?name=alice&enabled=true", f"ROUTE:/x-{token}|PARAMS:name=alice&enabled=true|VALID:1"),
        (f"/{token}/plain", f"ROUTE:/{token}/plain|PARAMS:none|VALID:1"),
    ]
    for url, expected in cases:
        result = subprocess.run([exe_path, url], capture_output=True, text=True, timeout=2)
        assert result.returncode == 0, f"url_router failed for {url!r}: {result.stderr}"
        assert result.stdout.strip() == expected, (
            f"Incorrect router output for {url!r}: expected {expected!r}, got {result.stdout.strip()!r}."
        )


def _commands_for_runner(path):
    suffix = os.path.splitext(path)[1].lower()
    commands = []
    if suffix == ".py":
        commands.append(["python3", path])
    elif suffix in (".sh", ".bash"):
        commands.append(["bash", path])
    elif suffix == ".js" and shutil.which("node"):
        commands.append(["node", path])
    elif suffix == ".rb" and shutil.which("ruby"):
        commands.append(["ruby", path])
    elif suffix == ".pl" and shutil.which("perl"):
        commands.append(["perl", path])
    if os.access(path, os.X_OK):
        direct = [path]
        if direct not in commands:
            commands.append(direct)
    return commands


def test_runner_reads_urls_executes_router_and_parses_output():
    candidates = [
        p for p in glob.glob(os.path.join(PROJECT_DIR, "test_runner.*"))
        if os.path.isfile(p) and re.fullmatch(r"test_runner\.[A-Za-z0-9_+-]+", os.path.basename(p))
    ]
    assert candidates, "No test_runner.* script exists in the project directory."

    router_path = os.path.join(PROJECT_DIR, "url_router")
    urls_path = os.path.join(PROJECT_DIR, "urls.txt")
    report_path = os.path.join(PROJECT_DIR, "report.json")
    call_log = os.path.join(PROJECT_DIR, ".verifier_router_calls")

    originals = {}
    for path in (router_path, urls_path, report_path):
        if os.path.exists(path):
            with open(path, "rb") as f:
                originals[path] = (f.read(), stat.S_IMODE(os.stat(path).st_mode))
        else:
            originals[path] = None

    token = secrets.token_hex(8)
    urls = [
        f"/runner/{token}/one?alpha=1&beta=two",
        f"/runner/{token}/without-query",
        f"/different/{token}?encoded=a%20b&flag=yes",
        f"/{token}/last",
        f"/extra/{token}?x=9&y=8&z=7",
    ]
    # Deliberately return values that cannot be inferred by simply splitting each URL.
    expected_outputs = {
        url: (f"/observed/{token}/{i}", "none" if i == 1 else f"probe={token}-{i}")
        for i, url in enumerate(urls)
    }

    probe_source = """#!/usr/bin/env python3
import json, sys
mapping = %r
with open(%r, "a") as log:
    log.write(json.dumps(sys.argv[1:] if len(sys.argv) > 1 else []) + "\\n")
if len(sys.argv) != 2 or sys.argv[1] not in mapping:
    print("VALID:0")
    raise SystemExit(1)
route, params = mapping[sys.argv[1]]
print(f"ROUTE:{route}|PARAMS:{params}|VALID:1")
""" % (expected_outputs, call_log)

    errors = []
    passed = False
    try:
        for candidate in sorted(candidates):
            commands = _commands_for_runner(candidate)
            if not commands:
                errors.append(f"{candidate}: no available interpreter and not executable")
                continue

            for command in commands:
                with open(router_path, "w") as f:
                    f.write(probe_source)
                os.chmod(router_path, 0o755)
                with open(urls_path, "w") as f:
                    f.write("\n".join(urls) + "\n")
                if os.path.exists(report_path):
                    os.remove(report_path)
                if os.path.exists(call_log):
                    os.remove(call_log)

                try:
                    run = subprocess.run(command, cwd=PROJECT_DIR, capture_output=True, text=True, timeout=15)
                except Exception as exc:
                    errors.append(f"{candidate}: {exc}")
                    continue
                if run.returncode != 0:
                    errors.append(f"{candidate}: exited {run.returncode}: {run.stderr.strip()}")
                    continue

                try:
                    with open(report_path) as f:
                        data = json.load(f)
                    with open(call_log) as f:
                        calls = [json.loads(line) for line in f if line.strip()]
                    expected_results = [
                        {
                            "original_url": url,
                            "parsed_route": expected_outputs[url][0],
                            "parsed_params": expected_outputs[url][1],
                        }
                        for url in urls
                    ]
                    assert data == {
                        "total_tested": len(urls),
                        "successful_executions": len(urls),
                        "results": expected_results,
                    }
                    invoked = collections.Counter(args[0] for args in calls if len(args) == 1)
                    assert all(invoked[url] >= 1 for url in urls)
                except Exception as exc:
                    errors.append(f"{candidate}: generated an incorrect report or did not invoke the router: {exc}")
                    continue

                passed = True
                break
            if passed:
                break
    finally:
        if os.path.exists(call_log):
            os.remove(call_log)
        for path, saved in originals.items():
            if saved is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                content, mode = saved
                with open(path, "wb") as f:
                    f.write(content)
                os.chmod(path, mode)

    assert passed, "No test_runner.* correctly read dynamic urls.txt, executed ./url_router, parsed its output, and generated report.json. " + " | ".join(errors)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
