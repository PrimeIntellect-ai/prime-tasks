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
import os
import re
import secrets
import stat
import subprocess
import tempfile

import pytest
import requests


def test_permissions_fixed():
    bin_dir = "/app/vulnerable_stack/bin"
    assert os.path.isdir(bin_dir), f"Directory {bin_dir} is missing."

    for filename in os.listdir(bin_dir):
        filepath = os.path.join(bin_dir, filename)
        if os.path.isfile(filepath):
            mode = os.stat(filepath).st_mode
            assert not (mode & stat.S_ISUID), f"File {filepath} still has the SUID bit set."
            assert not (mode & stat.S_IWOTH), f"File {filepath} is still world-writable."
            assert mode & stat.S_IXUSR, f"File {filepath} should be executable by the owner."


def make_ip(index):
    token = secrets.randbelow(200) + 1
    return f"198.51.{index}.{token}"


def run_detector(script_path, contents):
    with tempfile.NamedTemporaryFile(mode="w", delete=False) as tmp:
        tmp.write(contents)
        tmp_path = tmp.name
    try:
        return subprocess.run(
            ["bash", script_path, tmp_path],
            capture_output=True,
            text=True,
            timeout=5,
        )
    finally:
        os.remove(tmp_path)


def test_detect_script_uses_supplied_log_and_matches_requests():
    script_path = "/home/user/detect.sh"
    assert os.path.isfile(script_path), f"Intrusion detection script {script_path} is missing."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    attackers = [make_ip(i) for i in range(1, 5)]
    benign = [make_ip(i) for i in range(10, 15)]
    host_a = secrets.token_hex(6) + ".example"
    host_b = secrets.token_hex(6) + ".invalid"
    safe_path = "/" + secrets.token_hex(8)

    lines = [
        f'{attackers[0]} - - [11/Sep/2026:01:01:01 +0000] "GET /login?next=http://{host_a}/x HTTP/1.1" 302 0 "-" "audit"',
        f'{attackers[1]} - - [11/Sep/2026:01:01:02 +0000] "GET /login?mode=x&next=https://{host_b}/y HTTP/1.1" 302 0 "-" "audit"',
        f'{attackers[2]} - - [11/Sep/2026:01:01:03 +0000] "GET /login?next=//{host_a}/z&mode=x HTTP/1.1" 302 0 "-" "audit"',
        f'{attackers[3]} - - [11/Sep/2026:01:01:04 +0000] "GET /login?next=/prefix//{host_b} HTTP/1.1" 302 0 "-" "audit"',
        # Duplicate attacker must not produce duplicate output.
        f'{attackers[0]} - - [11/Sep/2026:01:01:05 +0000] "GET /login?next=https://{host_b}/again HTTP/1.1" 302 0 "-" "audit"',
        # Decoys: internal redirect, wrong method, wrong endpoint, and text only in referer.
        f'{benign[0]} - - [11/Sep/2026:01:01:06 +0000] "GET /login?next={safe_path} HTTP/1.1" 302 0 "-" "audit"',
        f'{benign[1]} - - [11/Sep/2026:01:01:07 +0000] "POST /login?next=http://{host_a} HTTP/1.1" 302 0 "-" "audit"',
        f'{benign[2]} - - [11/Sep/2026:01:01:08 +0000] "GET /other?next=http://{host_a} HTTP/1.1" 200 0 "-" "audit"',
        f'{benign[3]} - - [11/Sep/2026:01:01:09 +0000] "GET /login-help?next=//{host_a} HTTP/1.1" 200 0 "-" "audit"',
        f'{benign[4]} - - [11/Sep/2026:01:01:10 +0000] "GET /login?next={safe_path} HTTP/1.1" 302 0 "http://{host_a}/" "audit"',
    ]
    # Randomize the fixed ordering so output cannot be tailored to line positions.
    keyed = [(secrets.token_bytes(8), line) for line in lines]
    log = "\n".join(line for _, line in sorted(keyed)) + "\n"

    result = run_detector(script_path, log)
    assert result.returncode == 0, f"Script failed with exit code {result.returncode}. Stderr: {result.stderr}"
    output = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    assert len(output) == len(set(output)), f"Output contains duplicate IP addresses: {output}"
    assert set(output) == set(attackers), f"Expected {set(attackers)}, got {set(output)}"

    # A second, independently generated benign log ensures the script reads its argument.
    empty_result = run_detector(
        script_path,
        f'{make_ip(20)} - - [11/Sep/2026:02:00:00 +0000] "GET /login?next=/{secrets.token_hex(8)} HTTP/1.1" 302 0 "-" "audit"\n',
    )
    assert empty_result.returncode == 0
    assert empty_result.stdout.strip() == "", f"Expected no output for benign log, got {empty_result.stdout!r}"


def parse_cgi_location(output):
    for line in output.splitlines():
        if line.lower().startswith("location:"):
            return line.split(":", 1)[1].strip()
    return None


def invoke_login(query):
    script = "/app/vulnerable_stack/cgi-bin/login.cgi"
    env = os.environ.copy()
    env["QUERY_STRING"] = query
    env["REQUEST_METHOD"] = "GET"
    result = subprocess.run([script], env=env, capture_output=True, text=True, timeout=5)
    assert result.returncode == 0, f"login.cgi failed: {result.stderr}"
    assert re.search(r"(?im)^Status:\s*302(?:\s|$)", result.stdout), result.stdout
    return parse_cgi_location(result.stdout)


def test_login_cgi_is_bash_and_validates_dynamic_redirects():
    script = "/app/vulnerable_stack/cgi-bin/login.cgi"
    assert os.path.isfile(script), "login.cgi is missing"
    assert os.access(script, os.X_OK), "login.cgi is not executable"
    with open(script, "r", errors="replace") as f:
        first_line = f.readline().strip()
    assert first_line.startswith("#!") and "bash" in first_line, "login.cgi must be a Bash CGI script"

    internal = "/" + secrets.token_hex(10)
    domain = secrets.token_hex(8) + ".example"
    assert invoke_login("next=" + internal) == internal
    assert invoke_login("foo=1&next=" + internal + "&bar=2") == internal
    assert invoke_login("next=http://" + domain + "/a") == "/"
    assert invoke_login("next=https://" + domain + "/b") == "/"
    assert invoke_login("next=//" + domain + "/c") == "/"


def extract_location_block(config, path="/login"):
    pattern = re.compile(r"\blocation\s+(?:(?:=|\^~)\s+)?" + re.escape(path) + r"(?:\s|\{|$)")
    for match in pattern.finditer(config):
        start = config.find("{", match.end())
        if start < 0:
            continue
        depth = 0
        for pos in range(start, len(config)):
            if config[pos] == "{":
                depth += 1
            elif config[pos] == "}":
                depth -= 1
                if depth == 0:
                    return config[start + 1:pos]
    return None


def listening_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    pids.add(int(name))
                    break
        except (FileNotFoundError, PermissionError):
            continue
    return pids


def test_nginx_configuration_and_running_architecture():
    config_path = "/app/vulnerable_stack/nginx.conf"
    assert os.path.isfile(config_path), "nginx.conf is missing"
    with open(config_path, errors="replace") as f:
        config = re.sub(r"#.*", "", f.read())

    check = subprocess.run(
        ["nginx", "-t", "-c", config_path], capture_output=True, text=True, timeout=5
    )
    assert check.returncode == 0, f"Invalid nginx configuration: {check.stdout}\n{check.stderr}"
    assert re.search(r"\blisten\s+(?:[^;\s]+:)?8080(?:\s|;)", config), "Nginx must listen on port 8080"

    login_block = extract_location_block(config)
    assert login_block is not None, "nginx.conf has no /login location"
    assert re.search(r"\bfastcgi_pass\s+127\.0\.0\.1:8081\s*;", login_block), \
        "/login must use fastcgi_pass 127.0.0.1:8081"
    assert not re.search(r"\bproxy_pass\b|\breturn\s+30[1278]\b", login_block), \
        "/login must be handled through FastCGI, not a proxy or hard-coded redirect"

    nginx_pids = []
    for pid in listening_pids(8080):
        try:
            cmdline = open(f"/proc/{pid}/cmdline", "rb").read().replace(b"\0", b" ").decode(errors="replace")
            exe = os.path.basename(os.readlink(f"/proc/{pid}/exe"))
        except OSError:
            continue
        if "nginx" in exe.lower() or "nginx" in cmdline.lower():
            nginx_pids.append(pid)
    assert nginx_pids, "Port 8080 is not being served by Nginx"
    assert listening_pids(8081), "The FastCGI service is not listening on port 8081"


def test_live_redirects_with_dynamic_inputs():
    base_url = "http://127.0.0.1:8080/login"
    internal_paths = ["/" + secrets.token_hex(8), "/" + secrets.token_hex(5) + "/settings"]
    domain = secrets.token_hex(8) + ".example"
    cases = [
        (internal_paths[0], internal_paths[0]),
        (internal_paths[1], internal_paths[1]),
        ("http://" + domain + "/a", "/"),
        ("https://" + domain + "/b", "/"),
        ("//" + domain + "/c", "/"),
    ]
    for supplied, expected in cases:
        try:
            response = requests.get(
                base_url + "?next=" + supplied,
                allow_redirects=False,
                timeout=5,
                headers={"X-Verifier-Nonce": secrets.token_hex(12)},
            )
        except requests.exceptions.RequestException as exc:
            pytest.fail(f"Failed to connect to Nginx on port 8080: {exc}")
        assert response.status_code == 302, f"Expected 302 for {supplied!r}, got {response.status_code}"
        assert response.headers.get("Location") == expected, \
            f"For {supplied!r}, expected Location {expected!r}, got {response.headers.get('Location')!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
