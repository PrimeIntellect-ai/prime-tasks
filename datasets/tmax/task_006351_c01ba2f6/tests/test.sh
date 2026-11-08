#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import re
import shutil
import socket
import subprocess
import tempfile
import uuid
import urllib.error
import urllib.request

SCRIPT = "/home/user/generate_nginx.sh"
ROUTES = "/home/user/routes.conf"
CONF = "/home/user/nginx.conf"
BENCH = "/home/user/bench.log"
PATCH = "/home/user/fix.patch"

EXPECTED_ROUTES = """# Custom Routing definitions
# Format: PATH TARGET_PORT PARAM_CHECK
/api/v1 9001 token=secret
/web 9002 NONE
"""

ORIGINAL_SCRIPT = r'''#!/bin/bash
# Generates Nginx config from routes.conf
OUT="/home/user/nginx.conf"

cat <<INNER_EOF > "$OUT"
events { worker_connections 1024; }
http {
    server {
        listen 8080;
INNER_EOF

while read -r path port param; do
    # Skip comments and empty lines
    if [[ -z "$path" || "$path" == \#* ]]; then
        continue
    fi

    echo "        location $path {" >> "$OUT"

    if [ "$param" != "NONE" ]; then
        # Parse parameter check (e.g. token=secret)
        IFS='=' read -r key val <<< "$param"
        echo "            if (\$arg_$key != \"$val\") {" >> "$OUT"
        echo "                return 403;" >> "$OUT"
        echo "            }" >> "$OUT"


    echo "            proxy_pass http://127.0.0.1:$port;" >> "$OUT"
    echo "        }" >> "$OUT"
done < /home/user/routes.conf

cat <<INNER_EOF >> "$OUT"
    }
}
INNER_EOF
'''


def run(*args, **kwargs):
    return subprocess.run(args, capture_output=True, text=True, **kwargs)


def test_routes_file_is_the_requested_input():
    assert os.path.isfile(ROUTES), f"{ROUTES} does not exist"
    with open(ROUTES) as f:
        assert f.read() == EXPECTED_ROUTES


def test_generate_nginx_sh_fixed_and_actually_generates_from_routes():
    assert os.path.isfile(SCRIPT), f"{SCRIPT} does not exist"
    assert os.access(SCRIPT, os.X_OK), f"{SCRIPT} is not executable"

    result = run("bash", "-n", SCRIPT)
    assert result.returncode == 0, f"Syntax error in {SCRIPT}: {result.stderr}"

    original_routes = open(ROUTES, "rb").read()
    marker = uuid.uuid4().hex[:12]
    dynamic_routes = (
        "# verifier-generated routing definitions\n"
        f"/verify-{marker} 18761 check_{marker}=value_{marker}\n"
        f"/plain-{marker} 18762 NONE\n"
    )
    generated = ""
    try:
        with open(ROUTES, "w") as f:
            f.write(dynamic_routes)
        result = run(SCRIPT)
        assert result.returncode == 0, f"Generator failed: {result.stderr}"
        assert os.path.isfile(CONF), "Generator did not create nginx.conf"
        generated = open(CONF).read()
    finally:
        with open(ROUTES, "wb") as f:
            f.write(original_routes)
        rerun = run(SCRIPT)
        assert rerun.returncode == 0, f"Generator failed on the requested routes: {rerun.stderr}"

    assert re.findall(r"(?m)^\s*location\s+(\S+)\s*\{", generated) == [
        f"/verify-{marker}", f"/plain-{marker}"
    ]
    assert re.findall(r"proxy_pass\s+http://127\.0\.0\.1:(\d+);", generated) == ["18761", "18762"]
    assert f'if ($arg_check_{marker} != "value_{marker}") {{' in generated
    assert generated.count("return 403;") == 1


def test_nginx_conf_generated_correctly_and_is_complete_and_valid():
    assert os.path.isfile(CONF), f"{CONF} was not generated"
    content = open(CONF).read()

    # Preserve the original assertions.
    assert "location /api/v1 {" in content, "Missing 'location /api/v1 {' in nginx.conf"
    assert 'if ($arg_token != "secret") {' in content, "Missing query-parameter check in nginx.conf"
    assert "proxy_pass http://127.0.0.1:9001;" in content, "Missing API proxy_pass in nginx.conf"
    assert "location /web {" in content, "Missing 'location /web {' in nginx.conf"

    assert re.findall(r"(?m)^\s*listen\s+(\d+)\s*;", content) == ["8080"]
    assert re.findall(r"(?m)^\s*location\s+(\S+)\s*\{", content) == ["/api/v1", "/web"]
    assert re.findall(r"proxy_pass\s+http://127\.0\.0\.1:(\d+);", content) == ["9001", "9002"]
    assert content.count("return 403;") == 1
    assert "$arg_token" in content

    result = run("nginx", "-t", "-c", CONF)
    assert result.returncode == 0, f"Generated nginx.conf is invalid: {result.stderr}"


def test_bench_log_exists_and_is_realistic_for_the_required_command():
    assert os.path.isfile(BENCH), f"{BENCH} does not exist"
    content = open(BENCH).read()

    # Preserve the original assertion and validate the requested run's fields.
    assert "ApacheBench" in content, f"{BENCH} does not contain ApacheBench output"
    required = {
        "Server Hostname": "127.0.0.1",
        "Server Port": "8080",
        "Document Path": "/web/",
        "Concurrency Level": "5",
        "Complete requests": "50",
    }
    for field, expected in required.items():
        match = re.search(rf"(?m)^{re.escape(field)}:\s*(\S+)\s*$", content)
        assert match, f"Missing ApacheBench field: {field}"
        assert match.group(1) == expected, f"Incorrect {field}: {match.group(1)}"
    assert re.search(r"(?m)^Requests per second:\s*[0-9]+(?:\.[0-9]+)?\s+\[#/sec\]", content)
    assert re.search(r"(?m)^Time taken for tests:\s*[0-9]+(?:\.[0-9]+)?\s+seconds", content)


def test_fix_patch_and_original_backup_are_valid():
    assert os.path.isfile(PATCH), f"{PATCH} does not exist"
    content = open(PATCH).read()

    # Preserve the original assertions.
    assert "---" in content, f"{PATCH} does not look like a valid diff (missing '---')"
    assert "+++" in content, f"{PATCH} does not look like a valid diff (missing '+++')"

    backups = []
    for candidate in glob.glob("/home/user/generate_nginx.sh*"):
        if candidate == SCRIPT or not os.path.isfile(candidate):
            continue
        try:
            if open(candidate, "rb").read() == ORIGINAL_SCRIPT.encode():
                backups.append(candidate)
        except OSError:
            pass
    assert backups, "No backup of the original broken generate_nginx.sh was found"

    with tempfile.TemporaryDirectory() as td:
        target = os.path.join(td, "generate_nginx.sh")
        with open(target, "w") as f:
            f.write(ORIGINAL_SCRIPT)
        result = run("patch", "--batch", target, PATCH)
        assert result.returncode == 0, f"fix.patch is not an applicable unified patch: {result.stderr}{result.stdout}"
        assert open(target, "rb").read() == open(SCRIPT, "rb").read(), \
            "Applying fix.patch to the original does not reproduce the submitted fixed script"


def nginx_pids():
    result = run("pgrep", "nginx")
    assert result.returncode == 0, "Nginx does not appear to be running"
    return [int(x) for x in result.stdout.split()]


def listening_inodes_on_8080():
    found = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        if not os.path.exists(table):
            continue
        for line in open(table).read().splitlines()[1:]:
            fields = line.split()
            if len(fields) >= 10 and fields[1].split(":")[-1].upper() == "1F90" and fields[3] == "0A":
                found.add(fields[9])
    return found


def test_nginx_is_running_with_generated_configuration_on_8080():
    pids = nginx_pids()  # Preserve and strengthen the original process assertion.
    cmdlines = []
    owned_sockets = set()
    for pid in pids:
        try:
            cmdlines.append(open(f"/proc/{pid}/cmdline", "rb").read().replace(b"\0", b" ").decode(errors="replace"))
            for fd in glob.glob(f"/proc/{pid}/fd/*"):
                try:
                    link = os.readlink(fd)
                    match = re.fullmatch(r"socket:\[(\d+)\]", link)
                    if match:
                        owned_sockets.add(match.group(1))
                except OSError:
                    pass
        except OSError:
            pass

    assert any("nginx" in cmd and "-c /home/user/nginx.conf" in cmd for cmd in cmdlines), \
        "Running nginx master was not started with /home/user/nginx.conf"
    listeners = listening_inodes_on_8080()
    assert listeners, "Nothing is listening on TCP port 8080"
    assert listeners & owned_sockets, "The listener on port 8080 is not owned by an nginx process"

    def status(url):
        try:
            with urllib.request.urlopen(url, timeout=3) as response:
                return response.status
        except urllib.error.HTTPError as exc:
            return exc.code

    assert status("http://127.0.0.1:8080/api/v1") == 403
    assert status("http://127.0.0.1:8080/api/v1?token=wrong") == 403
    assert status("http://127.0.0.1:8080/api/v1?token=secret") != 403
    assert status("http://127.0.0.1:8080/web/") != 403
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
