#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import json
import os
import runpy
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

import pytest


def load_parser_module():
    filepath = "/home/user/parser.py"
    spec = importlib.util.spec_from_file_location("submitted_actlog_parser", filepath)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def request_json(url, timeout=5):
    req = urllib.request.Request(url, method="GET")
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return response.status, json.loads(response.read().decode("utf-8"))


def test_bench_result_exists_and_valid():
    """Check if /home/user/bench_result.txt exists and contains a valid float number."""
    filepath = "/home/user/bench_result.txt"
    assert os.path.exists(filepath), f"File {filepath} does not exist."
    assert os.path.isfile(filepath), f"{filepath} is not a file."

    with open(filepath, "r") as f:
        content = f.read().strip()

    assert content, f"File {filepath} is empty."

    try:
        val = float(content)
    except ValueError:
        pytest.fail(f"Content of {filepath} is not a valid float: {content}")

    assert val > 0, "Benchmark time should be greater than 0."


def test_api_projects_endpoint():
    """Check GET /projects returns the correct list of project names."""
    url = "http://localhost:8000/projects"
    try:
        status, data = request_json(url)
        assert status == 200, f"Expected status 200, got {status}"
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to API at {url}: {e}")

    expected = ["FrontendClient", "PaymentGateway", "DataPipeline"]
    assert isinstance(data, list), "Expected a JSON list response."
    assert set(data) == set(expected), f"Expected projects {expected}, got {data}"


def test_api_actions_endpoint_success():
    """Check GET /actions/PaymentGateway returns the correct actions and files."""
    url = "http://localhost:8000/actions/PaymentGateway"
    try:
        status, data = request_json(url)
        assert status == 200, f"Expected status 200, got {status}"
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to API at {url}: {e}")

    expected = [
        {"action": "refactor", "file": "app/services/stripe.py"},
        {"action": "secure", "file": "app/config/keys.py"},
        {"action": "test", "file": "tests/integration/test_stripe.py"}
    ]
    assert data == expected, f"Expected {expected}, got {data}"


def test_api_actions_endpoint_not_found():
    """Check GET /actions/UnknownProject returns 404."""
    url = "http://localhost:8000/actions/UnknownProject"
    try:
        request_json(url)
        pytest.fail("Expected 404 Not Found, but got 200 OK.")
    except urllib.error.HTTPError as e:
        assert e.code == 404, f"Expected status 404, got {e.code}"
        data = json.loads(e.read().decode("utf-8"))
        assert data.get("detail") == "Project not found", f"Expected 'Project not found' detail, got {data}"
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to API at {url}: {e}")


def test_parser_implementation():
    """Inspect /home/user/parser.py to ensure it uses a state-machine approach and contains ActLogParser."""
    filepath = "/home/user/parser.py"
    assert os.path.exists(filepath), f"File {filepath} does not exist."

    with open(filepath, "r") as f:
        source = f.read()

    try:
        tree = ast.parse(source)
    except SyntaxError as e:
        pytest.fail(f"Syntax error in {filepath}: {e}")

    classes = [node.name for node in ast.walk(tree) if isinstance(node, ast.ClassDef)]
    assert "ActLogParser" in classes, "Class ActLogParser not found in parser.py"
    assert "re." not in source and "import re" not in source, "Regular expressions (re module) should not be used."


def test_parser_executes_on_generated_valid_input():
    module = load_parser_module()
    assert hasattr(module.ActLogParser, "parse"), "ActLogParser.parse is missing"

    token = uuid.uuid4().hex
    project_a = "Alpha" + token
    project_b = "Beta" + token
    action_a = "edit_" + token
    action_b = "review_" + token
    action_c = "ship_" + token
    file_a = "src/" + token + ".py"
    file_b = "tests/" + token + ".py"
    file_c = "docs/" + token + ".md"
    content = (
        "# generated test input\n\n"
        f"BEGIN {project_a}\n"
        f"ACTION {action_a}\nFILE {file_a}\n"
        f"ACTION {action_b}\nFILE {file_b}\n"
        "END\n\n"
        f"BEGIN {project_b}\n"
        f"ACTION {action_c}\nFILE {file_c}\n"
        "END\n"
    )
    expected = {
        project_a: [
            {"action": action_a, "file": file_a},
            {"action": action_b, "file": file_b},
        ],
        project_b: [{"action": action_c, "file": file_c}],
    }

    fd, path = tempfile.mkstemp(suffix=".actlog")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(content)
        assert module.ActLogParser().parse(path) == expected
    finally:
        os.unlink(path)


@pytest.mark.parametrize("content", [
    "FILE orphan.txt\n",
    "ACTION orphan\nFILE orphan.txt\n",
    "BEGIN Outer\nBEGIN Inner\nEND\n",
    "BEGIN P\nFILE missing_action.txt\nEND\n",
    "BEGIN P\nACTION first\nACTION second\nFILE x\nEND\n",
    "BEGIN P\nACTION unfinished\nEND\n",
    "BEGIN P\nACTION unfinished\n",
    "BEGIN P\nACTION ok\nFILE x\n",
    "END\n",
    "BEGIN P\nUNKNOWN value\nEND\n",
])
def test_parser_rejects_generated_malformed_sequences(content):
    module = load_parser_module()
    fd, path = tempfile.mkstemp(suffix=".actlog")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(content)
        with pytest.raises(ValueError):
            module.ActLogParser().parse(path)
    finally:
        os.unlink(path)


def test_benchmark_script_executes_parser_exactly_50_times():
    benchmark = "/home/user/benchmark.py"
    assert os.path.exists(benchmark), f"File {benchmark} does not exist."
    assert os.path.isfile(benchmark), f"{benchmark} is not a file."

    with open(benchmark, "r") as f:
        source = f.read()
    try:
        ast.parse(source)
    except SyntaxError as e:
        pytest.fail(f"Syntax error in {benchmark}: {e}")

    parser_module = load_parser_module()
    original_parse = parser_module.ActLogParser.parse
    calls = []

    def counted_parse(self, filepath):
        calls.append(os.path.realpath(filepath))
        return original_parse(self, filepath)

    parser_module.ActLogParser.parse = counted_parse
    old_parser_module = sys.modules.get("parser")
    old_path = list(sys.path)
    original_perf_counter = time.perf_counter
    clock_calls = []

    def controlled_perf_counter():
        clock_calls.append(None)
        return 100.0 if len(clock_calls) == 1 else 105.0

    try:
        sys.modules["parser"] = parser_module
        sys.path.insert(0, "/home/user")
        time.perf_counter = controlled_perf_counter
        runpy.run_path(benchmark, run_name="__main__")
    finally:
        time.perf_counter = original_perf_counter
        sys.path[:] = old_path
        if old_parser_module is None:
            sys.modules.pop("parser", None)
        else:
            sys.modules["parser"] = old_parser_module

    expected_path = os.path.realpath("/home/user/large.actlog")
    assert calls == [expected_path] * 50, "benchmark.py must parse /home/user/large.actlog exactly 50 times"
    assert len(clock_calls) == 2, "benchmark.py must record one start and one end time with time.perf_counter()"

    with open("/home/user/bench_result.txt", "r") as f:
        result_text = f.read().strip()
    try:
        result = float(result_text)
    except ValueError:
        pytest.fail("benchmark.py did not write only a floating-point result")
    assert abs(result - 0.1) < 1e-12, "benchmark.py must write (end - start) / 50"


def test_api_uses_generated_log_and_caches_it_at_startup():
    api_path = "/home/user/api.py"
    assert os.path.isfile(api_path), f"File {api_path} does not exist."

    fixture_path = "/home/user/data/project.actlog"
    with open(fixture_path, "rb") as f:
        original_fixture = f.read()

    token = uuid.uuid4().hex
    projects = ["Web" + token, "Worker" + token, "Store" + token]
    expected_actions = {
        projects[0]: [{"action": "build_" + token, "file": "ui/" + token + ".js"}],
        projects[1]: [
            {"action": "queue_" + token, "file": "jobs/" + token + ".py"},
            {"action": "test_" + token, "file": "tests/" + token + ".py"},
        ],
        projects[2]: [{"action": "migrate_" + token, "file": "db/" + token + ".sql"}],
    }

    lines = ["# dynamically generated"]
    for project in projects:
        lines.append("BEGIN " + project)
        for item in expected_actions[project]:
            lines.append("ACTION " + item["action"])
            lines.append("FILE " + item["file"])
        lines.append("END")
        lines.append("")
    generated_fixture = "\n".join(lines).encode("utf-8")

    sock = socket.socket()
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
    sock.close()

    proc = None
    try:
        with open(fixture_path, "wb") as f:
            f.write(generated_fixture)

        env = os.environ.copy()
        env["PYTHONPATH"] = "/home/user" + os.pathsep + env.get("PYTHONPATH", "")
        proc = subprocess.Popen(
            [sys.executable, "-m", "uvicorn", "api:app", "--host", "127.0.0.1", "--port", str(port)],
            cwd="/home/user",
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

        base = f"http://127.0.0.1:{port}"
        deadline = time.time() + 12
        last_error = None
        while time.time() < deadline:
            if proc.poll() is not None:
                pytest.fail("api.py could not be started by uvicorn")
            try:
                status, returned_projects = request_json(base + "/projects", timeout=1)
                if status == 200:
                    break
            except urllib.error.URLError as e:
                last_error = e
                time.sleep(0.1)
        else:
            pytest.fail(f"Generated API instance did not become ready: {last_error}")

        assert isinstance(returned_projects, list)
        assert set(returned_projects) == set(projects), "API did not expose projects from the generated log"

        for project in projects:
            encoded = urllib.parse.quote(project, safe="")
            status, data = request_json(base + "/actions/" + encoded)
            assert status == 200
            assert data == expected_actions[project]

        missing = "Missing" + token
        try:
            request_json(base + "/actions/" + urllib.parse.quote(missing, safe=""))
            pytest.fail("Expected generated unknown project to return 404")
        except urllib.error.HTTPError as e:
            assert e.code == 404
            assert json.loads(e.read().decode("utf-8")) == {"detail": "Project not found"}

        replacement = f"BEGIN Replacement{token}\nACTION changed\nFILE changed.txt\nEND\n"
        with open(fixture_path, "w") as f:
            f.write(replacement)

        status, cached_projects = request_json(base + "/projects")
        assert status == 200
        assert set(cached_projects) == set(projects), "API must parse the file once at startup and retain it in memory"
        status, cached_actions = request_json(base + "/actions/" + urllib.parse.quote(projects[0], safe=""))
        assert status == 200
        assert cached_actions == expected_actions[projects[0]]
    finally:
        if proc is not None and proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=5)
        with open(fixture_path, "wb") as f:
            f.write(original_fixture)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
