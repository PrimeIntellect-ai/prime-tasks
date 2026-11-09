#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import random
import re
import secrets
import string
import subprocess
import urllib.error
import urllib.parse
import urllib.request

import pytest

PROJECT = "/home/user/project"
EXPECTED_PROCESSOR = '''from flask import Flask, request, jsonify
import ctypes

app = Flask(__name__)

cruncher = ctypes.CDLL('./libcruncher.so')
cruncher.get_length.argtypes = [ctypes.c_char_p]
cruncher.get_length.restype = ctypes.c_int

@app.route('/api/process', methods=['GET'])
def process_data():
    data = request.args.get('data', '')
    length = cruncher.get_length(data.encode('utf-8'))
    return jsonify({"original": data, "length": length})
'''


def http_get(url):
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, timeout=5) as response:
        return response.status, response.read()


def listening_socket_owners(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[3] == "0A":
                        local_port = int(fields[1].rsplit(":", 1)[1], 16)
                        if local_port == port:
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass

    owners = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            links = [os.readlink(os.path.join(fd_dir, fd)) for fd in os.listdir(fd_dir)]
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if not any(link.startswith("socket:[") and link[8:-1] in inodes for link in links):
            continue
        try:
            exe = os.path.realpath(f"/proc/{name}/exe")
            with open(f"/proc/{name}/cmdline", "rb") as f:
                cmdline = f.read().replace(b"\0", b" ").decode("utf-8", "replace")
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        owners.append((int(name), exe, cmdline))
    return owners


def test_final_output_json():
    output_path = "/home/user/final_output.json"
    assert os.path.isfile(output_path), f"Expected output file {output_path} does not exist."
    with open(output_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {output_path} does not contain valid JSON.")

    expected = {"original": "helloworld", "length": 10}
    assert data == expected, f"Expected JSON {expected}, but got {data}."

    status, live_raw = http_get("http://127.0.0.1:8080/api/process?data=helloworld")
    assert status == 200
    with open(output_path, "rb") as f:
        saved_raw = f.read()
    assert saved_raw == live_raw, "final_output.json is not the raw response currently returned by the proxy."


def test_patch_was_applied():
    processor_path = os.path.join(PROJECT, "processor.py")
    with open(processor_path, "r") as f:
        content = f.read()
    assert content == EXPECTED_PROCESSOR, "processor.py does not contain exactly the result of applying fixes.patch."

    result = subprocess.run(
        ["patch", "--dry-run", "--batch", "-R", "processor.py", "fixes.patch"],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    assert result.returncode == 0, f"fixes.patch is not reversibly applied to processor.py:\n{result.stdout}"


def test_libcruncher_so_exists():
    so_path = os.path.join(PROJECT, "libcruncher.so")
    assert os.path.isfile(so_path), f"Shared library {so_path} was not created."
    with open(so_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "libcruncher.so is not an ELF shared object."

    lib = ctypes.CDLL(so_path)
    func = lib.get_length
    func.argtypes = [ctypes.c_char_p]
    func.restype = ctypes.c_int
    assert func(None) == 0
    rng = random.SystemRandom()
    for _ in range(12):
        value = "".join(rng.choice(string.ascii_letters + string.digits + " _-") for _ in range(rng.randrange(0, 150)))
        encoded = value.encode("utf-8")
        assert func(encoded) == len(encoded), f"get_length returned the wrong result for {value!r}."


def test_pyproject_toml_exists():
    toml_path = os.path.join(PROJECT, "pyproject.toml")
    assert os.path.isfile(toml_path), f"pyproject.toml is missing at {toml_path}."
    with open(toml_path, "r") as f:
        content = f.read()
    assert "data_org" in content or "data-org" in content, "Package name 'data_org' not found in pyproject.toml."
    assert "Flask" in content, "Flask dependency not found in pyproject.toml."
    assert "gunicorn" in content, "gunicorn dependency not found in pyproject.toml."

    try:
        import tomllib
    except ImportError:
        import tomli as tomllib
    with open(toml_path, "rb") as f:
        config = tomllib.load(f)
    build = config.get("build-system", {})
    assert build.get("build-backend", "").startswith("setuptools.build_meta"), "setuptools is not the build backend."
    assert any(str(item).lower().split("[")[0].split("=")[0].split(">") [0].strip() == "setuptools" for item in build.get("requires", [])), "setuptools is missing from build requirements."
    project = config.get("project", {})
    assert str(project.get("name", "")).lower().replace("-", "_") == "data_org"
    dependencies = [str(item).lower() for item in project.get("dependencies", [])]
    assert any(re.match(r"^flask(?:\s|\[|[<>=!~])", item) or item == "flask" for item in dependencies)
    assert any(re.match(r"^gunicorn(?:\s|\[|[<>=!~])", item) or item == "gunicorn" for item in dependencies)


def test_venv_exists():
    venv_path = "/home/user/venv"
    assert os.path.isdir(venv_path), f"Virtual environment directory {venv_path} does not exist."
    python_bin = os.path.join(venv_path, "bin", "python")
    assert os.path.isfile(python_bin), f"Python executable not found in {venv_path}/bin/."
    result = subprocess.run(
        [python_bin, "-c", "from importlib.metadata import version; import flask, gunicorn; print(version('data_org'))"],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert result.returncode == 0, f"data_org and its dependencies are not installed in the virtual environment: {result.stderr}"
    assert result.stdout.strip(), "Installed data_org distribution has no version metadata."


def test_nginx_conf_exists():
    nginx_conf_path = "/home/user/nginx.conf"
    assert os.path.isfile(nginx_conf_path), f"Nginx configuration file {nginx_conf_path} does not exist."
    with open(nginx_conf_path, "r") as f:
        content = f.read()
    uncommented = re.sub(r"#.*", "", content)
    assert not re.search(r"(?m)^\s*user\s+", uncommented), "nginx.conf must not contain a user directive."
    required_patterns = [
        r"\blisten\s+8080\s*;",
        r"\bpid\s+/home/user/nginx\.pid\s*;",
        r"\baccess_log\s+/home/user/nginx_access\.log(?:\s+\w+)?\s*;",
        r"\berror_log\s+/home/user/nginx_error\.log(?:\s+\w+)?\s*;",
        r"\blocation\s+[^\{]*?/api/[^\{]*\{",
        r"\bproxy_pass\s+http://127\.0\.0\.1:5000(?:/[^;]*)?\s*;",
    ]
    for directive in ("client_body_temp_path", "proxy_temp_path", "fastcgi_temp_path", "uwsgi_temp_path", "scgi_temp_path"):
        required_patterns.append(rf"\b{directive}\s+/tmp/?(?:\s|;)")
    for pattern in required_patterns:
        assert re.search(pattern, uncommented), f"Required Nginx configuration is missing: {pattern}"
    result = subprocess.run(["nginx", "-t", "-c", nginx_conf_path], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    assert result.returncode == 0, f"Nginx configuration is invalid:\n{result.stdout}"
    assert os.path.isfile("/home/user/nginx_access.log")
    assert os.path.isfile("/home/user/nginx_error.log")
    assert os.path.isfile("/home/user/nginx.pid")


def test_nginx_running():
    try:
        output = subprocess.check_output(["ps", "aux"]).decode("utf-8")
        assert "nginx" in output, "Nginx process is not running."
    except subprocess.CalledProcessError:
        pytest.fail("Failed to check running processes.")

    owners = listening_socket_owners(8080)
    assert owners, "No process is listening on port 8080."
    assert any(os.path.basename(exe) == "nginx" for _, exe, _ in owners), f"Port 8080 is not owned by Nginx: {owners}"
    nginx_cmdlines = []
    for pid in os.listdir("/proc"):
        if pid.isdigit():
            try:
                with open(f"/proc/{pid}/cmdline", "rb") as f:
                    cmd = f.read().replace(b"\0", b" ").decode("utf-8", "replace")
                if "nginx: master process" in cmd or re.search(r"(^| )nginx( |$)", cmd):
                    nginx_cmdlines.append(cmd)
            except (FileNotFoundError, PermissionError, ProcessLookupError):
                pass
    assert any("-c /home/user/nginx.conf" in cmd for cmd in nginx_cmdlines), "Running Nginx was not started with /home/user/nginx.conf."


def test_gunicorn_running():
    try:
        output = subprocess.check_output(["ps", "aux"]).decode("utf-8")
        assert "gunicorn" in output, "Gunicorn process is not running."
    except subprocess.CalledProcessError:
        pytest.fail("Failed to check running processes.")

    owners = listening_socket_owners(5000)
    assert owners, "No process is listening on port 5000."
    matching = [cmd for _, _, cmd in owners if "gunicorn" in cmd]
    assert matching, f"Port 5000 is not owned by Gunicorn: {owners}"
    assert any("/home/user/venv" in cmd for cmd in matching), "Gunicorn was not started from /home/user/venv."
    assert any("processor:app" in cmd for cmd in matching), "Gunicorn is not serving processor:app."
    assert any("127.0.0.1:5000" in cmd for cmd in matching), "Gunicorn is not bound as requested."


def test_nginx_proxy_response():
    url = "http://127.0.0.1:8080/api/process?data=test"
    try:
        status, raw = http_get(url)
        assert status == 200, f"Expected HTTP 200, got {status}"
        data = json.loads(raw.decode("utf-8"))
        assert data == {"original": "test", "length": 4}, f"Unexpected response from proxy: {data}"
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to Nginx proxy on port 8080: {e}")

    values = ["", secrets.token_urlsafe(9)]
    alphabet = string.ascii_letters + string.digits + " _-"
    rng = random.SystemRandom()
    values.extend("".join(rng.choice(alphabet) for _ in range(rng.randrange(1, 180))) for _ in range(8))
    for value in values:
        query = urllib.parse.urlencode({"data": value})
        expected = {"original": value, "length": len(value.encode("utf-8"))}
        for base in ("http://127.0.0.1:5000", "http://127.0.0.1:8080"):
            status, raw = http_get(f"{base}/api/process?{query}")
            assert status == 200
            assert json.loads(raw.decode("utf-8")) == expected, f"Incorrect response from {base} for randomized input {value!r}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
