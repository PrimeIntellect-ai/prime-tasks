#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.machinery
import inspect
import json
import os
import re
import secrets
import shutil
import string
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request

WORKSPACE = "/home/user/workspace"


def test_rust_ext_fixed_and_installed():
    try:
        import rust_ext
    except ImportError:
        assert False, "rust_ext module is not installed or cannot be imported. Did you run `maturin develop`?"

    # Preserve the original functional assertion.
    try:
        result = rust_ext.process_string("test")
        assert result == "testtest", f"rust_ext.process_string('test') returned '{result}', expected 'testtest'"
    except Exception as e:
        assert False, f"rust_ext.process_string failed with error: {e}"

    # The installed artifact must be a native extension, not a Python stand-in.
    origin = getattr(rust_ext, "__file__", None)
    assert origin and os.path.isfile(origin), f"rust_ext has no installed module artifact: {origin!r}"
    assert any(origin.endswith(suffix) for suffix in importlib.machinery.EXTENSION_SUFFIXES), \
        f"rust_ext must be a compiled Python extension, not {origin}"
    assert inspect.isbuiltin(rust_ext.process_string), "process_string is not implemented by the native extension"

    # Compile the submitted Rust source and exercise the installed native function
    # on verifier-selected values rather than one fixed example.
    result = subprocess.run(
        ["cargo", "check", "--quiet"],
        cwd=os.path.join(WORKSPACE, "rust_ext"),
        capture_output=True,
        text=True,
        timeout=240,
    )
    assert result.returncode == 0, f"The submitted Rust source does not compile:\n{result.stdout}\n{result.stderr}"

    alphabet = string.ascii_letters + string.digits + " _-"
    random_values = [
        "".join(secrets.choice(alphabet) for _ in range(secrets.randbelow(80) + 1))
        for _ in range(12)
    ]
    values = ["", "a", "with spaces", "é漢🙂", "line1\nline2", "x" * 4097] + random_values
    for value in values:
        actual = rust_ext.process_string(value)
        assert actual == value + value, f"process_string failed for verifier-selected input {value!r}"


def _run_submission_with_fake(test_file, faulty):
    temp_dir = tempfile.mkdtemp(prefix="property-check-")
    try:
        copied_test = os.path.join(temp_dir, "test_submission.py")
        shutil.copyfile(test_file, copied_test)
        log_file = os.path.join(temp_dir, "calls.jsonl")
        fake_module = os.path.join(temp_dir, "rust_ext.py")
        with open(fake_module, "w", encoding="utf-8") as f:
            f.write(
                "import json, os\n"
                "def process_string(s):\n"
                "    with open(os.environ['RUST_EXT_CALL_LOG'], 'a', encoding='utf-8') as out:\n"
                "        out.write(json.dumps(s) + '\\n')\n"
                "    result = s + s\n"
                "    if os.environ.get('RUST_EXT_FAULTY') == '1':\n"
                "        result += '\\x00FAULT'\n"
                "    return result\n"
            )
        env = os.environ.copy()
        env["PYTHONPATH"] = temp_dir
        env["RUST_EXT_CALL_LOG"] = log_file
        env["RUST_EXT_FAULTY"] = "1" if faulty else "0"
        result = subprocess.run(
            [sys.executable, "-m", "pytest", "-q", copied_test],
            cwd=temp_dir,
            env=env,
            capture_output=True,
            text=True,
            timeout=180,
        )
        calls = []
        if os.path.isfile(log_file):
            with open(log_file, encoding="utf-8") as f:
                calls = [json.loads(line) for line in f if line.strip()]
        return result, calls
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


def test_property_based_test_exists_and_passes():
    test_file = os.path.join(WORKSPACE, "test_ext.py")
    assert os.path.isfile(test_file), f"Test file {test_file} does not exist."

    with open(test_file, "r", encoding="utf-8") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "hypothesis" in content, "The test file does not seem to use the hypothesis library."
    assert "test_process_string_property" in content, "The test function 'test_process_string_property' is missing."

    result = subprocess.run(
        [sys.executable, "-m", "pytest", test_file], capture_output=True, text=True, timeout=180
    )
    assert result.returncode == 0, f"pytest failed on {test_file}:\n{result.stdout}\n{result.stderr}"

    tree = ast.parse(content, filename=test_file)
    target = next(
        (node for node in ast.walk(tree)
         if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
         and node.name == "test_process_string_property"),
        None,
    )
    assert target is not None, "The required property test function is not defined."
    uses_text = any(
        isinstance(node, ast.Call)
        and ((isinstance(node.func, ast.Attribute) and node.func.attr == "text")
             or (isinstance(node.func, ast.Name) and node.func.id == "text"))
        for node in ast.walk(target)
    )
    assert uses_text, "test_process_string_property must use hypothesis.strategies.text()."

    # Run the submitted test against controlled implementations. It must exercise
    # many generated strings, accept the correct behavior, and reject an incorrect one.
    good_result, calls = _run_submission_with_fake(test_file, faulty=False)
    assert good_result.returncode == 0, \
        f"The property test rejected a correct implementation:\n{good_result.stdout}\n{good_result.stderr}"
    assert len(set(calls)) >= 10, "The property test did not exercise enough distinct generated strings."

    bad_result, _ = _run_submission_with_fake(test_file, faulty=True)
    assert bad_result.returncode != 0, "The property test passes an implementation that does not return s + s."


def test_nginx_config_exists_and_valid():
    conf_file = os.path.join(WORKSPACE, "nginx.conf")
    assert os.path.isfile(conf_file), f"Nginx config file {conf_file} does not exist."

    with open(conf_file, "r", encoding="utf-8") as f:
        content = f.read()

    # Preserve all original configuration assertions.
    assert "8080" in content, "Nginx config does not seem to listen on port 8080."
    assert "127.0.0.1:5000" in content, "Nginx config does not seem to proxy to 127.0.0.1:5000."
    assert "pid" in content, "Nginx config does not specify a pid directive."
    assert "worker_processes 1" in content or "worker_processes  1" in content, "Nginx config does not set worker_processes to 1."
    assert "events" in content, "Nginx config does not contain an events block."

    assert re.search(r"\bpid\s+/home/user/workspace/nginx\.pid\s*;", content), \
        "Nginx must use /home/user/workspace/nginx.pid."
    assert re.search(r"\berror_log\s+/home/user/workspace/[^;]*;", content), \
        "error_log must point into /home/user/workspace/."
    assert re.search(r"\baccess_log\s+/home/user/workspace/[^;]*;", content), \
        "access_log must point into /home/user/workspace/."

    parsed = subprocess.run(
        ["nginx", "-t", "-c", conf_file], capture_output=True, text=True, timeout=30
    )
    assert parsed.returncode == 0, f"Nginx rejected the submitted configuration:\n{parsed.stdout}\n{parsed.stderr}"


def test_live_reverse_proxy_and_response_file():
    conf_file = os.path.join(WORKSPACE, "nginx.conf")
    response_file = os.path.join(WORKSPACE, "response.txt")
    assert os.path.isfile(response_file), f"Response file {response_file} does not exist."

    with open(response_file, "r", encoding="utf-8") as f:
        content = f.read().strip()

    # Preserve the original response assertion.
    expected = "platformplatform"
    assert content == expected, f"Expected response.txt to contain '{expected}', but found '{content}'"

    # Stop agent-leftover instances so the check starts the provided app and the
    # submitted Nginx configuration itself.
    subprocess.run(["pkill", "-x", "nginx"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-f", "/home/user/workspace/app.py"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.5)

    app_log = open("/tmp/verifier-flask.log", "w")
    nginx_log = open("/tmp/verifier-nginx.log", "w")
    app_proc = subprocess.Popen(
        [sys.executable, os.path.join(WORKSPACE, "app.py")],
        cwd=WORKSPACE,
        stdout=app_log,
        stderr=subprocess.STDOUT,
    )
    nginx_proc = None
    try:
        nginx_proc = subprocess.Popen(
            ["nginx", "-c", conf_file],
            cwd=WORKSPACE,
            stdout=nginx_log,
            stderr=subprocess.STDOUT,
        )

        probe = "verify_" + secrets.token_hex(16)
        url = "http://127.0.0.1:8080/process?" + urllib.parse.urlencode({"text": probe})
        body = None
        last_error = None
        for _ in range(50):
            assert app_proc.poll() is None, "The provided Flask app exited before serving requests."
            if nginx_proc.poll() not in (None, 0):
                raise AssertionError("Nginx exited with an error while using the submitted config.")
            try:
                with urllib.request.urlopen(url, timeout=2) as response:
                    body = response.read().decode("utf-8")
                break
            except Exception as exc:
                last_error = exc
                time.sleep(0.2)
        assert body is not None, f"The reverse proxy did not become ready: {last_error}"
        assert body == probe + probe, f"Live proxy returned {body!r}, expected {(probe + probe)!r}"

        with urllib.request.urlopen("http://127.0.0.1:8080/process?text=platform", timeout=3) as response:
            live_platform = response.read().decode("utf-8")
        assert live_platform == content, "response.txt does not match the live proxied platform response."
    finally:
        subprocess.run(["nginx", "-s", "quit", "-c", conf_file], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if nginx_proc is not None and nginx_proc.poll() is None:
            nginx_proc.terminate()
            try:
                nginx_proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                nginx_proc.kill()
        if app_proc.poll() is None:
            app_proc.terminate()
            try:
                app_proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                app_proc.kill()
        app_log.close()
        nginx_log.close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
