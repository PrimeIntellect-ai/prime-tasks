#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import hashlib
import http.client
import os
import signal
import stat
import subprocess
import time


def test_result_log():
    log_path = "/home/user/result.log"
    assert os.path.isfile(log_path), f"File {log_path} is missing."

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) >= 2, f"{log_path} must contain at least two lines."

    expected_password = "secr3t_vault!"
    expected_token = "TOKEN=" + hashlib.md5((expected_password + "_salt123").encode()).hexdigest()

    assert lines[0] == expected_password, f"Line 1 of {log_path} is incorrect. Expected the cracked password."
    assert lines[1] == expected_token, f"Line 2 of {log_path} is incorrect. Expected the generated token."


def test_sandbox_script():
    script_path = "/home/user/sandbox.sh"
    assert os.path.isfile(script_path), f"Script {script_path} is missing."

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {script_path} is not executable."

    with open(script_path, "r") as f:
        content = f.read()

    assert "env -i" in content, f"{script_path} must use 'env -i' to clear environment variables."
    assert "PATH=/usr/bin:/usr/local/bin:/bin" in content, f"{script_path} must explicitly set PATH."

    expected_password = "secr3t_vault!"
    expected_token = "TOKEN=" + hashlib.md5((expected_password + "_salt123").encode()).hexdigest()

    assert f"AUTH_TOKEN={expected_token}" in content or f"AUTH_TOKEN='{expected_token}'" in content or f'AUTH_TOKEN="{expected_token}"' in content, f"{script_path} must pass the token as AUTH_TOKEN."
    assert "python3 /home/user/audit/server.py" in content, f"{script_path} must start the python server."


def test_server_csp_header():
    server_path = "/home/user/audit/server.py"
    assert os.path.isfile(server_path), f"File {server_path} is missing."

    with open(server_path, "r") as f:
        content = f.read()

    expected_header1 = "self.send_header('Content-Security-Policy', \"default-src 'self'; script-src 'none';\")"
    expected_header2 = "self.send_header(\"Content-Security-Policy\", \"default-src 'self'; script-src 'none';\")"
    expected_header3 = 'self.send_header(\'Content-Security-Policy\', \'default-src \\\'self\\\'; script-src \\\'none\\\';\')'

    header_found = any(h in content for h in [expected_header1, expected_header2, expected_header3])

    # Preserve the original source-level assertions in addition to exercising it below.
    assert "Content-Security-Policy" in content, f"CSP header name missing in {server_path}."
    assert "default-src 'self'; script-src 'none';" in content, f"CSP header value missing or incorrect in {server_path}."


def _descendants(root_pid):
    descendants = {root_pid}
    changed = True
    while changed:
        changed = False
        for name in os.listdir("/proc"):
            if not name.isdigit():
                continue
            try:
                with open(f"/proc/{name}/status", "r") as f:
                    fields = dict(
                        line.split(":", 1) for line in f.read().splitlines() if ":" in line
                    )
                ppid = int(fields["PPid"].strip())
            except (OSError, KeyError, ValueError):
                continue
            pid = int(name)
            if ppid in descendants and pid not in descendants:
                descendants.add(pid)
                changed = True
    return descendants


def _find_server_process(root_pid):
    for pid in _descendants(root_pid):
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                argv = [part.decode(errors="replace") for part in f.read().split(b"\0") if part]
        except OSError:
            continue
        if "/home/user/audit/server.py" in argv:
            return pid
    return None


def _read_environment(pid):
    with open(f"/proc/{pid}/environ", "rb") as f:
        entries = [entry for entry in f.read().split(b"\0") if entry]
    result = {}
    for entry in entries:
        key, value = entry.split(b"=", 1)
        result[key.decode(errors="replace")] = value.decode(errors="replace")
    return result


def test_sandbox_execution_and_http_behavior():
    expected_password = "secr3t_vault!"
    expected_token = "TOKEN=" + hashlib.md5((expected_password + "_salt123").encode()).hexdigest()
    expected_csp = "default-src 'self'; script-src 'none';"

    inherited_env = {
        "PATH": "/definitely/not/the/required/path",
        "HOME": "/tmp/verifier-home-must-not-leak",
        "SHELL": "/tmp/verifier-shell-must-not-leak",
        "VERIFIER_SECRET_ONE": "must-be-cleared-1",
        "VERIFIER_SECRET_TWO": "must-be-cleared-2",
        "AUTH_TOKEN": "WRONG_INHERITED_TOKEN",
    }

    proc = subprocess.Popen(
        ["/home/user/sandbox.sh"],
        env=inherited_env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        start_new_session=True,
    )

    try:
        server_pid = None
        last_error = None
        deadline = time.time() + 8
        while time.time() < deadline:
            if proc.poll() is not None:
                out, err = proc.communicate(timeout=1)
                raise AssertionError(
                    "sandbox.sh exited before serving requests: "
                    + (out + err).decode(errors="replace")
                )

            server_pid = _find_server_process(proc.pid)
            if server_pid is not None:
                try:
                    conn = http.client.HTTPConnection("127.0.0.1", 8080, timeout=1)
                    conn.request("GET", "/")
                    response = conn.getresponse()
                    body = response.read()
                    break
                except OSError as exc:
                    last_error = exc
                finally:
                    try:
                        conn.close()
                    except Exception:
                        pass
            time.sleep(0.1)
        else:
            raise AssertionError(f"sandbox.sh did not start the required server: {last_error}")

        assert server_pid is not None, "sandbox.sh did not execute /home/user/audit/server.py."

        server_env = _read_environment(server_pid)
        assert server_env.get("PATH") == "/usr/bin:/usr/local/bin:/bin", "Server PATH is not the required constrained PATH."
        assert server_env.get("AUTH_TOKEN") == expected_token, "Server did not receive the generated AUTH_TOKEN."
        for forbidden in ("HOME", "SHELL", "VERIFIER_SECRET_ONE", "VERIFIER_SECRET_TWO"):
            assert forbidden not in server_env, f"env -i did not clear inherited variable {forbidden}."

        assert response.status == 200, "The server did not return HTTP 200."
        assert response.headers.get_all("Content-Security-Policy") == [expected_csp], "HTTP 200 response is missing the exact CSP header."
        assert expected_token.encode() in body, "The running server did not receive AUTH_TOKEN from sandbox.sh."

        for path in ("/another-path", "/nested/test"):
            conn = http.client.HTTPConnection("127.0.0.1", 8080, timeout=2)
            try:
                conn.request("GET", path)
                extra_response = conn.getresponse()
                extra_response.read()
                assert extra_response.status == 200, f"GET {path} did not return HTTP 200."
                assert extra_response.headers.get_all("Content-Security-Policy") == [expected_csp], f"HTTP 200 response for {path} is missing the exact CSP header."
            finally:
                conn.close()
    finally:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            proc.wait(timeout=2)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
