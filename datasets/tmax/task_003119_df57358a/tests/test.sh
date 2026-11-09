#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import re
import subprocess
import sys
import tempfile
import urllib.request

APP_DIR = "/home/user/app"
DATA_PATH = APP_DIR + "/data.txt"
CONF_PATH = APP_DIR + "/nginx.conf"


def get_json(url):
    req = urllib.request.Request(url, headers={"Cache-Control": "no-cache"})
    with urllib.request.urlopen(req, timeout=5) as response:
        assert response.status == 200, f"Expected HTTP 200 from {url}, got {response.status}"
        return json.loads(response.read().decode("utf-8"))


def listening_processes(port):
    inodes = set()
    port_hex = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[1].rsplit(":", 1)[1].upper() == port_hex and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    owners = []
    for procdir in glob.glob("/proc/[0-9]*"):
        pid = int(procdir.rsplit("/", 1)[1])
        try:
            links = [os.readlink(fd) for fd in glob.glob(procdir + "/fd/*")]
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if not any(link.startswith("socket:[") and link[8:-1] in inodes for link in links):
            continue
        try:
            exe = os.path.realpath(procdir + "/exe")
            with open(procdir + "/cmdline", "rb") as f:
                cmdline = f.read().replace(b"\0", b" ").decode("utf-8", "replace")
            with open(procdir + "/maps", "r", errors="replace") as f:
                maps = f.read()
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        owners.append((pid, exe, cmdline, maps))
    return owners


def test_result_json():
    result_path = "/home/user/result.json"
    assert os.path.exists(result_path), f"File {result_path} does not exist."
    with open(result_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{result_path} does not contain valid JSON."
    assert "result" in data, f"{result_path} JSON does not contain the 'result' key."
    assert data["result"] == 50, f"Expected result to be 50, but got {data['result']}."


def test_nginx_running_and_proxying():
    try:
        data = get_json("http://127.0.0.1:8080/process")
        assert data.get("result") == 50, "Nginx proxy did not return the expected result."
    except Exception as e:
        assert False, f"Failed to connect to Nginx on port 8080 or proxy failed: {e}"


def test_app_py_running():
    try:
        data = get_json("http://127.0.0.1:9000/process")
        assert data.get("result") == 50, "app.py did not return the expected result."
    except Exception as e:
        assert False, f"Failed to connect to app.py on port 9000: {e}"


def test_extension_linked_correctly():
    so_files = glob.glob(APP_DIR + "/pyprocessor*.so")
    assert so_files, "Could not find compiled pyprocessor extension (pyprocessor*.so) in /home/user/app/"
    so_file = so_files[0]
    try:
        result = subprocess.run(["ldd", so_file], capture_output=True, text=True, check=True)
    except subprocess.CalledProcessError as e:
        assert False, f"ldd failed on {so_file}: {e.stderr}"
    output = result.stdout
    expected_path = "/home/user/app/lib/libprocessor.so"
    found = any("libprocessor.so" in line and expected_path in line for line in output.splitlines())
    assert found, f"libprocessor.so is not correctly linked to {expected_path} in {so_file}. ldd output:\n{output}"

    dynamic = subprocess.run(["readelf", "-d", so_file], capture_output=True, text=True, check=True).stdout
    assert re.search(r"\((?:RUNPATH|RPATH)\).*\[/home/user/app/lib(?:[:\]])", dynamic), \
        f"The extension does not contain an rpath for /home/user/app/lib:\n{dynamic}"

    values = [random.SystemRandom().randint(-100000, 100000) for _ in range(6)]
    code = "import pyprocessor,sys,json; print(json.dumps([pyprocessor.multiply_by_two(x) for x in json.loads(sys.argv[1])]))"
    proc = subprocess.run([sys.executable, "-c", code, json.dumps(values)], cwd=APP_DIR,
                          capture_output=True, text=True, check=True)
    assert json.loads(proc.stdout) == [2 * x for x in values], "Compiled pyprocessor returned incorrect values."


def test_nginx_conf_exists():
    assert os.path.exists(CONF_PATH), f"Nginx configuration {CONF_PATH} does not exist."
    assert os.path.isfile(CONF_PATH), f"{CONF_PATH} is not a file."


def test_actual_processes_and_configuration():
    nginx_owners = listening_processes(8080)
    assert nginx_owners, "No process is listening on port 8080."
    assert any(os.path.basename(exe) == "nginx" for _, exe, _, _ in nginx_owners), \
        f"Port 8080 is not owned by Nginx: {[(p, e, c) for p, e, c, _ in nginx_owners]}"
    assert any(os.path.basename(exe) == "nginx" and CONF_PATH in cmd for _, exe, cmd, _ in nginx_owners), \
        "The Nginx process listening on 8080 was not started with /home/user/app/nginx.conf."

    checked = subprocess.run(["nginx", "-T", "-c", CONF_PATH], capture_output=True, text=True)
    rendered = checked.stdout + checked.stderr
    assert checked.returncode == 0, f"nginx rejected {CONF_PATH}:\n{rendered}"
    assert re.search(r"\blisten\s+8080\b", rendered), "Effective Nginx configuration does not listen on 8080."
    assert re.search(r"\bproxy_pass\s+http://127\.0\.0\.1:9000\s*;", rendered), \
        "Effective Nginx configuration does not proxy to 127.0.0.1:9000."

    app_owners = listening_processes(9000)
    assert app_owners, "No process is listening on port 9000."
    app_processes = [x for x in app_owners if "/home/user/app/app.py" in x[2]]
    assert app_processes, f"Port 9000 is not owned by python3 /home/user/app/app.py: {[(p, e, c) for p, e, c, _ in app_owners]}"
    assert any("pyprocessor" in maps and "/home/user/app/lib/libprocessor.so" in maps
               for _, _, _, maps in app_processes), \
        "The running app.py process has not loaded pyprocessor and /home/user/app/lib/libprocessor.so."


def test_parse_data_calls_pyprocessor_and_obeys_state_machine():
    rng = random.SystemRandom()
    a, b, ignored1, ignored2 = [rng.randint(-10000, 10000) for _ in range(4)]
    multiplier = rng.randint(3, 11)
    offset = rng.randint(20, 100)
    commands = f"VAL {ignored1}\nSTART\nVAL {a}\nSTOP\nVAL {ignored2}\nSTART\nVAL {b}\nSTOP\n"
    expected = (a * multiplier + offset) + (b * multiplier + offset)
    code = r'''
import app, json, os, sys, tempfile
commands, multiplier, offset = json.loads(sys.argv[1])
def transformed(value):
    return value * multiplier + offset
app.pyprocessor.multiply_by_two = transformed
fd, path = tempfile.mkstemp(text=True)
try:
    os.write(fd, commands.encode())
    os.close(fd)
    print(app.parse_data(path))
finally:
    try: os.close(fd)
    except OSError: pass
    os.unlink(path)
'''
    proc = subprocess.run([sys.executable, "-c", code, json.dumps([commands, multiplier, offset])],
                          cwd=APP_DIR, capture_output=True, text=True, check=True)
    assert int(proc.stdout.strip()) == expected, \
        "parse_data did not implement the required states using pyprocessor.multiply_by_two."


def test_endpoints_process_fresh_unpredictable_data():
    rng = random.SystemRandom()
    with open(DATA_PATH, "rb") as f:
        original = f.read()
    cases = []
    for _ in range(3):
        ignored = rng.randint(-50000, 50000)
        x, y, z = [rng.randint(-50000, 50000) for _ in range(3)]
        commands = (
            f"VAL {ignored}\nSTART\nVAL {x}\nVAL {y}\nSTOP\n"
            f"VAL {ignored + 1}\nSTART\nVAL {z}\nSTOP\nVAL {ignored + 2}\n"
        )
        cases.append((commands, 2 * (x + y + z)))
    try:
        for index, (commands, expected) in enumerate(cases):
            tmp = DATA_PATH + ".verifier-tmp"
            with open(tmp, "w") as f:
                f.write(commands)
            os.replace(tmp, DATA_PATH)
            nonce = rng.getrandbits(64)
            direct = get_json(f"http://127.0.0.1:9000/process?verify={nonce}-{index}")
            proxied = get_json(f"http://127.0.0.1:8080/process?verify={nonce}-{index}")
            assert direct.get("result") == expected, \
                f"Direct app did not process fresh data: expected {expected}, got {direct}"
            assert proxied.get("result") == expected, \
                f"Nginx endpoint did not proxy the fresh app result: expected {expected}, got {proxied}"
    finally:
        with open(DATA_PATH, "wb") as f:
            f.write(original)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
