#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import os
import subprocess
from pathlib import Path

import pytest
from flask import Flask

PATCHED_APP = "/home/user/patched_app.py"
GRADER = "/app/grade_security.py"
EXPECTED_TOKEN = "SUPER_SECRET_SSH_TOKEN_999"
EXPECTED_ROUTE = "/hidden_admin_77/diag"


def test_patched_app_security_score():
    # Preserve the original verifier's assertions.
    assert os.path.exists(PATCHED_APP), f"Patched app not found at {PATCHED_APP}."
    assert os.path.isfile(PATCHED_APP), f"{PATCHED_APP} is not a file."
    assert os.path.exists(GRADER), f"Grader script not found at {GRADER}."

    result = subprocess.run(
        ["python3", GRADER, PATCHED_APP],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Grader failed: {result.stderr}"
    try:
        score = float(result.stdout.strip())
    except ValueError:
        pytest.fail(f"Grader did not output a float: {result.stdout!r}")
    assert score >= 1.0, f"Security score is {score}, expected >= 1.0."


def test_patched_application_behaviour(monkeypatch):
    calls = []

    def record(kind, positional, keyword):
        command = positional[0] if positional else keyword.get("args")
        supplied_env = keyword.get("env")
        effective_env = dict(os.environ if supplied_env is None else supplied_env)
        calls.append({
            "kind": kind,
            "command": command,
            "kwargs": dict(keyword),
            "env": effective_env,
        })
        return command

    class DummyPopen:
        def __init__(self, *args, **kwargs):
            self.args = record("Popen", args, kwargs)
            self.returncode = 0
            self.pid = 4242

        def communicate(self, input=None, timeout=None):
            return (b"", b"")

        def wait(self, timeout=None):
            return 0

        def poll(self):
            return 0

        def kill(self):
            self.returncode = -9

        def terminate(self):
            self.returncode = -15

        def __enter__(self):
            return self

        def __exit__(self, *exc):
            return False

    def fake_check_output(*args, **kwargs):
        record("check_output", args, kwargs)
        return "diagnostic ok" if kwargs.get("text") or kwargs.get("universal_newlines") else b"diagnostic ok"

    def fake_run(*args, **kwargs):
        command = record("run", args, kwargs)
        output = "diagnostic ok" if kwargs.get("text") or kwargs.get("universal_newlines") else b"diagnostic ok"
        return subprocess.CompletedProcess(command, 0, stdout=output, stderr="" if isinstance(output, str) else b"")

    def fake_call(*args, **kwargs):
        record("call", args, kwargs)
        return 0

    # Prevent the submitted module from launching real commands while importing
    # or servicing the test request, while retaining the exact launch details.
    monkeypatch.setattr(subprocess, "Popen", DummyPopen)
    monkeypatch.setattr(subprocess, "check_output", fake_check_output)
    monkeypatch.setattr(subprocess, "run", fake_run)
    monkeypatch.setattr(subprocess, "call", fake_call)

    spec = importlib.util.spec_from_file_location("submitted_patched_app", PATCHED_APP)
    assert spec is not None and spec.loader is not None, "Patched app is not importable Python."
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    apps = [value for value in vars(module).values() if isinstance(value, Flask)]
    assert apps, "Patched file must define a Flask application."
    app = apps[0]
    app.config.update(TESTING=True)

    calls.clear()
    marker = Path("/tmp/diag_injection_succeeded")
    marker.unlink(missing_ok=True)
    target = "127.0.0.1; touch /tmp/diag_injection_succeeded"

    response = app.test_client().get(
        EXPECTED_ROUTE,
        query_string={"target": target, "username": "auditor"},
    )
    assert response.status_code < 400, f"Diagnostic endpoint returned {response.status_code}."
    assert not marker.exists(), "The diagnostic target was interpreted as shell syntax."

    cookie_headers = response.headers.getlist("Set-Cookie")
    session_headers = [h.lower() for h in cookie_headers if h.lower().startswith("session=")]
    assert session_headers, "The endpoint did not create the session cookie."
    assert any("httponly" in h and "secure" in h for h in session_headers), (
        "The session cookie must include both HttpOnly and Secure attributes."
    )

    target_calls = []
    for call in calls:
        command = call["command"]
        if isinstance(command, (list, tuple)) and target in [str(item) for item in command]:
            target_calls.append(call)

    assert target_calls, "No diagnostic subprocess received the requested target as a separate argument."
    for call in target_calls:
        command = call["command"]
        assert call["kwargs"].get("shell") is not True, "Diagnostic subprocess enables shell execution."
        executable = os.path.basename(str(command[0])).lower()
        assert executable not in {"sh", "bash", "dash", "zsh", "cmd", "powershell"}, (
            "Diagnostic input is being passed through a command shell."
        )

    background_calls = [call for call in calls if call["kind"] == "Popen"]
    assert background_calls, "The endpoint did not trigger the required background process."

    token_env_calls = [
        call for call in background_calls
        if EXPECTED_TOKEN in {str(value) for value in call["env"].values()}
    ]
    assert token_env_calls, "The SSH management token was not supplied to the background process via its environment."
    for call in token_env_calls:
        assert EXPECTED_TOKEN not in repr(call["command"]), (
            "The SSH management token is still exposed in command-line arguments."
        )
TEST_EOF

if timeout 40s python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
