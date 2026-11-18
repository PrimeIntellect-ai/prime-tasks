#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import signal
import stat
import subprocess
import time
import urllib.request
import pytest


def stop_group(proc):
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


def wait_for_url(url, expected=None, attempts=20):
    for _ in range(attempts):
        try:
            with urllib.request.urlopen(url, timeout=1) as response:
                body = response.read().decode(errors="replace")
                if response.status == 200 and (expected is None or expected in body):
                    return True
        except Exception:
            pass
        time.sleep(0.25)
    return False


def test_start_api_expect_script():
    exp_path = "/home/user/start_api.exp"
    assert os.path.isfile(exp_path), f"File {exp_path} is missing."

    with open(exp_path, "r") as f:
        content = f.read()
    assert "SRE-8891" in content, "Expect script does not contain the correct passcode."

    # Preserve the original functional assertion against the shipped legacy API.
    proc = subprocess.Popen(
        ["expect", exp_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        start_new_session=True
    )
    try:
        assert wait_for_url("http://127.0.0.1:9000/"), \
            "The expect script failed to start the server on port 9000 successfully."
    finally:
        stop_group(proc)

    # Instrument the required legacy path and verify that Expect actually invokes it
    # and supplies both requested answers, rather than directly starting another server.
    legacy = "/home/user/legacy_api.sh"
    original = open(legacy, "rb").read()
    original_mode = stat.S_IMODE(os.stat(legacy).st_mode)
    transcript = "/tmp/legacy_api_transcript"
    server_py = "/tmp/legacy_probe_server.py"
    token = "legacy-probe-" + secrets.token_hex(12)
    try:
        try:
            os.unlink(transcript)
        except FileNotFoundError:
            pass
        with open(server_py, "w") as f:
            f.write("from http.server import BaseHTTPRequestHandler, HTTPServer\n")
            f.write(f"TOKEN={token!r}\n")
            f.write("class H(BaseHTTPRequestHandler):\n")
            f.write(" def do_GET(self):\n  self.send_response(200); self.end_headers(); self.wfile.write(TOKEN.encode())\n")
            f.write(" def log_message(self, *args): pass\n")
            f.write("HTTPServer(('127.0.0.1',9000), H).serve_forever()\n")
        with open(legacy, "w") as f:
            f.write("#!/bin/bash\n")
            f.write("read -p 'Enter SRE passcode: ' pass\n")
            f.write("read -p 'Start server? (y/n): ' confirm\n")
            f.write("printf '%s\\n%s\\n' \"$pass\" \"$confirm\" > /tmp/legacy_api_transcript\n")
            f.write("[ \"$pass\" = 'SRE-8891' ] && [ \"$confirm\" = 'y' ] || exit 41\n")
            f.write("exec python3 /tmp/legacy_probe_server.py\n")
        os.chmod(legacy, 0o755)

        proc = subprocess.Popen(
            ["expect", exp_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            start_new_session=True
        )
        try:
            assert wait_for_url("http://127.0.0.1:9000/", token), \
                "start_api.exp did not invoke and automate /home/user/legacy_api.sh."
            assert os.path.isfile(transcript), "The required legacy script was not invoked."
            with open(transcript) as f:
                answers = f.read().splitlines()
            assert answers == ["SRE-8891", "y"], \
                f"Expected the passcode and confirmation, received: {answers!r}"
        finally:
            stop_group(proc)
    finally:
        with open(legacy, "wb") as f:
            f.write(original)
        os.chmod(legacy, original_mode)
        for path in (transcript, server_py):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass


def parse_haproxy_sections(content):
    sections = []
    current = None
    for raw in content.splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        match = re.match(r"^(global|defaults|frontend|backend|listen)\b(?:\s+(\S+))?", line, re.I)
        if match:
            current = {"kind": match.group(1).lower(), "name": match.group(2), "lines": []}
            sections.append(current)
        elif current is not None:
            current["lines"].append(line)
    return sections


def test_haproxy_config():
    cfg_path = "/home/user/haproxy.cfg"
    assert os.path.isfile(cfg_path), f"File {cfg_path} is missing."

    with open(cfg_path, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "8080" in content, "HAProxy config missing port 8080."
    assert "9000" in content, "HAProxy config missing port 9000."
    result = subprocess.run(["haproxy", "-c", "-f", cfg_path], capture_output=True, text=True)
    assert result.returncode == 0, f"HAProxy config syntax check failed:\n{result.stderr}"

    sections = parse_haproxy_sections(content)
    globals_ = [s for s in sections if s["kind"] == "global"]
    for section in globals_:
        for line in section["lines"]:
            directive = line.split()[0].lower()
            assert directive not in {"daemon", "user", "group"}, \
                f"Forbidden privileged/background global directive: {directive}"

    frontends = [s for s in sections if s["kind"] == "frontend"]
    backends = {s["name"]: s for s in sections if s["kind"] == "backend"}
    matching_frontends = [
        s for s in frontends
        if any(re.match(r"^bind\s+127\.0\.0\.1:8080(?:\s|$)", line, re.I) for line in s["lines"])
    ]
    assert matching_frontends, "No frontend actively binds 127.0.0.1:8080."

    routed_names = set()
    for frontend in matching_frontends:
        for line in frontend["lines"]:
            match = re.match(r"^(?:default_backend|use_backend)\s+(\S+)", line, re.I)
            if match:
                routed_names.add(match.group(1))
    assert routed_names, "The port 8080 frontend does not route to a backend."
    assert any(
        name in backends and any(
            re.match(r"^server\s+\S+\s+127\.0\.0\.1:9000(?:\s|$)", line, re.I)
            for line in backends[name]["lines"]
        )
        for name in routed_names
    ), "The routed backend has no server at 127.0.0.1:9000."

    token = "haproxy-probe-" + secrets.token_hex(12)
    backend_code = (
        "from http.server import BaseHTTPRequestHandler,HTTPServer\n"
        f"T={token!r}\n"
        "class H(BaseHTTPRequestHandler):\n"
        " def do_GET(self):\n  self.send_response(200); self.end_headers(); self.wfile.write(T.encode())\n"
        " def log_message(self,*a): pass\n"
        "HTTPServer(('127.0.0.1',9000),H).serve_forever()\n"
    )
    backend = subprocess.Popen(
        ["python3", "-c", backend_code], stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL, start_new_session=True
    )
    proxy = None
    try:
        time.sleep(0.3)
        proxy = subprocess.Popen(
            ["haproxy", "-db", "-f", cfg_path], stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, start_new_session=True
        )
        assert wait_for_url("http://127.0.0.1:8080/", token), \
            "HAProxy did not forward 127.0.0.1:8080 to 127.0.0.1:9000."
    finally:
        if proxy is not None:
            stop_group(proxy)
        stop_group(backend)


def test_monitor_script():
    script_path = "/home/user/monitor.sh"
    log_path = "/home/user/uptime.log"
    assert os.path.isfile(script_path), f"File {script_path} is missing."
    assert os.access(script_path, os.X_OK), f"File {script_path} is not executable."

    # Preserve the original real reachability assertions.
    subprocess.run([script_path], capture_output=True, timeout=6)
    assert os.path.isfile(log_path), f"Log file {log_path} was not created."
    with open(log_path) as f:
        lines = f.read().strip().split("\n")
    assert lines[-1] == "DOWN", "Monitor script did not log 'DOWN' when the server is unreachable."

    dummy_server = subprocess.Popen(
        ["python3", "-m", "http.server", "8080"], stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL, start_new_session=True
    )
    try:
        time.sleep(0.7)
        subprocess.run([script_path], capture_output=True, timeout=6)
        with open(log_path) as f:
            lines = f.read().strip().split("\n")
        assert lines[-1] == "UP", "Monitor script did not log 'UP' when the server is reachable."
    finally:
        stop_group(dummy_server)

    # Replace curl briefly so its arguments and exit status are controlled by the test.
    curl_path = "/usr/bin/curl"
    saved_curl = "/usr/bin/curl.verifier-original"
    call_log = "/tmp/monitor_curl_calls"
    if os.path.lexists(saved_curl):
        os.unlink(saved_curl)
    os.rename(curl_path, saved_curl)
    try:
        with open(curl_path, "w") as f:
            f.write("#!/bin/sh\n")
            f.write("printf 'CALL\\n' >> \"$CURL_TEST_LOG\"\n")
            f.write("printf '%s\\n' \"$@\" >> \"$CURL_TEST_LOG\"\n")
            f.write("exit \"$CURL_TEST_EXIT\"\n")
        os.chmod(curl_path, 0o755)
        try:
            os.unlink(log_path)
        except FileNotFoundError:
            pass

        outcomes = [0, 0, 7, 7]
        secrets.SystemRandom().shuffle(outcomes)
        expected_lines = []
        for code in outcomes:
            try:
                os.unlink(call_log)
            except FileNotFoundError:
                pass
            env = os.environ.copy()
            env["CURL_TEST_LOG"] = call_log
            env["CURL_TEST_EXIT"] = str(code)
            subprocess.run([script_path], env=env, capture_output=True, timeout=6)
            expected_lines.append("UP" if code == 0 else "DOWN")

            assert os.path.isfile(call_log), "monitor.sh did not execute curl."
            with open(call_log) as f:
                records = f.read().splitlines()
            assert records and records[0] == "CALL", "monitor.sh did not execute curl."
            args = records[1:]
            assert "http://127.0.0.1:8080/" in args, \
                "curl was not called with http://127.0.0.1:8080/."
            silent = "--silent" in args or any(
                a.startswith("-") and not a.startswith("--") and "s" in a[1:]
                for a in args
            )
            assert silent, "curl was not called in silent mode."
            timeout_ok = "--max-time=2" in args or "-m2" in args
            for i, arg in enumerate(args[:-1]):
                if arg in ("--max-time", "-m") and args[i + 1] == "2":
                    timeout_ok = True
            assert timeout_ok, "curl was not called with a maximum timeout of 2 seconds."

            with open(log_path) as f:
                actual_lines = f.read().splitlines()
            assert actual_lines == expected_lines, \
                "monitor.sh must append exactly UP or DOWN according to curl's exit code."
    finally:
        try:
            os.unlink(curl_path)
        except FileNotFoundError:
            pass
        os.rename(saved_curl, curl_path)
        try:
            os.unlink(call_log)
        except FileNotFoundError:
            pass


def test_crontab_txt():
    cron_path = "/home/user/crontab.txt"
    assert os.path.isfile(cron_path), f"File {cron_path} is missing."

    with open(cron_path, "r") as f:
        content = f.read().strip()

    match = re.search(r"^\s*\*/5\s+\*\s+\*\s+\*\s+\*\s+/home/user/monitor\.sh\s*$", content, re.MULTILINE)
    assert match is not None, f"Crontab file does not contain the correct schedule. Found:\n{content}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
