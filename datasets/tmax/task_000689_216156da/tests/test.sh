#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import http.client
import os
import random
import secrets
import shlex
import signal
import string
import subprocess
import time
import urllib.parse

import pytest


def test_start_env_script_exists():
    """Check that the startup script exists and is executable."""
    script_path = "/home/user/start_env.sh"
    assert os.path.isfile(script_path), f"Startup script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Startup script {script_path} is not executable."


def test_nginx_config_csp_and_proxy():
    """Verify Nginx configuration contains the required CSP and proxy settings."""
    nginx_conf_path = "/app/target_env/nginx/nginx.conf"
    assert os.path.isfile(nginx_conf_path), f"Nginx config {nginx_conf_path} does not exist."

    with open(nginx_conf_path, "r") as f:
        content = f.read()

    assert "proxy_pass http://127.0.0.1:5000" in content or "proxy_pass http://localhost:5000" in content, \
        "Nginx config does not proxy traffic to the Flask app on port 5000."
    assert "listen 8080" in content, "Nginx config does not listen on port 8080."

    csp_directive = "Content-Security-Policy"
    assert csp_directive in content, "Nginx config is missing the Content-Security-Policy header."
    assert "script-src 'self'" in content, "CSP does not restrict script-src to 'self'."
    assert "object-src 'self'" in content, "CSP does not restrict object-src to 'self'."


def _stop_existing_services():
    subprocess.run(["redis-cli", "-h", "127.0.0.1", "shutdown", "nosave"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-x", "nginx"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-x", "redis-server"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-f", "/app/target_env/flask"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.5)


def _has_pair(args, option, value):
    return any(args[i] == option and args[i + 1] == value for i in range(len(args) - 1))


def test_startup_flow_and_network_policy():
    """Run the startup artifact, verify all services, and inspect its firewall calls."""
    script_path = "/home/user/start_env.sh"
    wrapper_path = "/app/bin/mock_iptables"
    log_path = "/tmp/mock_iptables.calls"

    assert os.path.isfile(script_path), f"Startup script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Startup script {script_path} is not executable."
    assert os.path.isfile(wrapper_path), f"iptables wrapper {wrapper_path} does not exist."

    _stop_existing_services()
    with open(wrapper_path, "rb") as f:
        original_wrapper = f.read()
    original_mode = os.stat(wrapper_path).st_mode
    if os.path.exists(log_path):
        os.unlink(log_path)

    instrumented = '''#!/bin/bash
printf '%q ' "$@" >> /tmp/mock_iptables.calls
printf '\\n' >> /tmp/mock_iptables.calls
echo "Mock iptables called with args: $@"
'''
    try:
        with open(wrapper_path, "w") as f:
            f.write(instrumented)
        os.chmod(wrapper_path, 0o755)

        process = subprocess.Popen(
            [script_path],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
            start_new_session=True,
        )
        try:
            _, stderr = process.communicate(timeout=15)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.communicate()
            pytest.fail("start_env.sh did not finish after launching the services in the background")
        assert process.returncode == 0, f"start_env.sh failed with exit code {process.returncode}: {stderr}"
        time.sleep(1)
    finally:
        with open(wrapper_path, "wb") as f:
            f.write(original_wrapper)
        os.chmod(wrapper_path, original_mode)

    assert os.path.isfile(log_path), "start_env.sh never invoked /app/bin/mock_iptables"
    with open(log_path, "r") as f:
        calls = [shlex.split(line) for line in f if line.strip()]

    owner_values = {"flask_user"}
    try:
        import pwd
        owner_values.add(str(pwd.getpwnam("flask_user").pw_uid))
    except KeyError:
        pass

    def owned_by_flask(args):
        return any(_has_pair(args, option, owner)
                   for option in ("--uid-owner", "--owner-uid")
                   for owner in owner_values)

    accept_indexes = [
        i for i, args in enumerate(calls)
        if _has_pair(args, "-j", "ACCEPT")
        and _has_pair(args, "--dport", "6379")
        and (_has_pair(args, "-p", "tcp") or _has_pair(args, "--protocol", "tcp"))
        and owned_by_flask(args)
    ]
    drop_indexes = [
        i for i, args in enumerate(calls)
        if _has_pair(args, "-j", "DROP")
        and owned_by_flask(args)
        and "--dport" not in args
        and "-p" not in args
        and "--protocol" not in args
    ]
    assert accept_indexes, "No rule allows flask_user TCP access to Redis port 6379"
    assert drop_indexes, "No rule drops all other outbound traffic owned by flask_user"
    assert min(accept_indexes) < max(drop_indexes), "The Redis allow rule must precede the outbound drop rule"

    redis_result = subprocess.run(
        ["redis-cli", "-h", "127.0.0.1", "-p", "6379", "ping"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=5
    )
    assert redis_result.returncode == 0 and redis_result.stdout.strip() == "PONG", \
        "Redis was not launched successfully by start_env.sh"

    marker = secrets.token_hex(8)
    requested_location = f"/verified/{marker}"
    path = "/login?next=" + urllib.parse.quote(requested_location, safe="")
    last_error = None
    response = None
    for _ in range(20):
        try:
            connection = http.client.HTTPConnection("127.0.0.1", 8080, timeout=2)
            connection.request("GET", path)
            response = connection.getresponse()
            response.read()
            connection.close()
            break
        except OSError as exc:
            last_error = exc
            time.sleep(0.25)

    assert response is not None, f"Nginx did not serve port 8080 after startup: {last_error}"
    assert response.status in (301, 302, 303, 307, 308), \
        f"Login request was not proxied to Flask; received HTTP {response.status}"
    assert response.getheader("Location") == requested_location, \
        "The proxied Flask login response did not preserve the requested redirect"
    csp = response.getheader("Content-Security-Policy") or ""
    assert "script-src 'self'" in csp, "Live Nginx response lacks the required script-src CSP"
    assert "object-src 'self'" in csp, "Live Nginx response lacks the required object-src CSP"


def _run_waf(waf_script, inputs):
    process = subprocess.run(
        ["python3", waf_script],
        input="".join(value + "\n" for value in inputs),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert process.returncode == 0, f"WAF script exited with {process.returncode}: {process.stderr}"
    return process.stdout.splitlines()


def test_waf_mock_adversarial_corpus():
    """Retain the supplied corpus checks."""
    waf_script = "/home/user/waf_mock.py"
    clean_corpus = "/app/corpora/clean_urls.txt"
    evil_corpus = "/app/corpora/evil_payloads.txt"

    assert os.path.isfile(waf_script), f"WAF mock script {waf_script} does not exist."
    assert os.path.isfile(clean_corpus), f"Clean corpus {clean_corpus} does not exist."
    assert os.path.isfile(evil_corpus), f"Evil corpus {evil_corpus} does not exist."

    with open(clean_corpus, "r") as f:
        clean_urls = [line.strip() for line in f if line.strip()]
    with open(evil_corpus, "r") as f:
        evil_urls = [line.strip() for line in f if line.strip()]

    clean_bypassed = []
    for url in clean_urls:
        output = _run_waf(waf_script, [url])
        if output != ["CLEAN"]:
            clean_bypassed.append(url)

    evil_bypassed = []
    for url in evil_urls:
        output = _run_waf(waf_script, [url])
        if output != ["EVIL"]:
            evil_bypassed.append(url)

    error_messages = []
    if evil_bypassed:
        error_messages.append(f"{len(evil_bypassed)} of {len(evil_urls)} evil bypassed. Offending URLs: {', '.join(evil_bypassed[:5])}...")
    if clean_bypassed:
        error_messages.append(f"{len(clean_bypassed)} of {len(clean_urls)} clean modified/rejected. Offending URLs: {', '.join(clean_bypassed[:5])}...")
    if error_messages:
        pytest.fail(" | ".join(error_messages))


def test_waf_mock_generated_adversarial_inputs():
    """Exercise parsing categories with fresh values that cannot be line-hardcoded."""
    waf_script = "/home/user/waf_mock.py"
    assert os.path.isfile(waf_script), f"WAF mock script {waf_script} does not exist."

    token = "".join(secrets.choice(string.ascii_lowercase) for _ in range(14))
    hostile_host = token + ".invalid"
    mixed_js = "JaVaScRiPt:alert(1)"
    nested_js = urllib.parse.quote(urllib.parse.quote(mixed_js, safe=""), safe="")
    nested_slashes = urllib.parse.quote(urllib.parse.quote("//" + hostile_host + "/x", safe=""), safe="")

    cases = [
        (f"/{token}/dashboard", "CLEAN"),
        (f"?next=/{token}/profile", "CLEAN"),
        (f"https://example.com/{token}/settings", "CLEAN"),
        (f"https:example.com/{token}", "EVIL"),
        (f"//{hostile_host}/{token}", "EVIL"),
        (f"/\\{hostile_host}/{token}", "EVIL"),
        (f"/%5c{hostile_host}/{token}", "EVIL"),
        (f"https://example.com@{hostile_host}/{token}", "EVIL"),
        (f"https://example.com%00@{hostile_host}/{token}", "EVIL"),
        (mixed_js, "EVIL"),
        (nested_js, "EVIL"),
        (f"data:text/html,<script>{token}</script>", "EVIL"),
        (nested_slashes, "EVIL"),
        (f"https://2130706433/{token}", "EVIL"),
        (f"https://0177.0.0.1/{token}", "EVIL"),
        (f"https://0x7f000001/{token}", "EVIL"),
    ]
    random.SystemRandom().shuffle(cases)
    inputs = [case[0] for case in cases]
    expected = [case[1] for case in cases]
    actual = _run_waf(waf_script, inputs)

    assert len(actual) == len(expected), \
        f"WAF must print exactly one result per input line; expected {len(expected)}, got {len(actual)}"
    failures = [(inputs[i], expected[i], actual[i]) for i in range(len(expected)) if actual[i] != expected[i]]
    assert not failures, "Generated WAF cases failed: " + repr(failures[:5])
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
