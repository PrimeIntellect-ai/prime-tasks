#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import json
import os
import random
import re
import shutil
import signal
import subprocess
import sys
import time
import urllib.error
import urllib.request

PROJECT = "/home/user/project"
LIB = os.path.join(PROJECT, "libcalc.so")
PARSER = os.path.join(PROJECT, "parser.py")
SERVER = os.path.join(PROJECT, "server.py")


def fetch(url, timeout=5):
    req = urllib.request.Request(url, method="GET")
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return response.getcode(), response.read().decode("utf-8").strip()


def actual_symbol():
    output = subprocess.check_output(["nm", "-D", LIB], text=True)
    matches = []
    for line in output.splitlines():
        fields = line.split()
        if fields and "_asm_calc_" in fields[-1]:
            matches.append(fields[-1])
    assert len(matches) == 1, f"Expected exactly one _asm_calc_ export, found {matches}"
    return matches[0]


def actual_result(symbol):
    library = ctypes.CDLL(LIB)
    function = getattr(library, symbol)
    function.argtypes = [ctypes.c_int, ctypes.c_int]
    function.restype = ctypes.c_int
    return function(5, 7)


def test_result_json():
    json_path = os.path.join(PROJECT, "result.json")
    assert os.path.isfile(json_path), f"{json_path} does not exist."
    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{json_path} is not valid JSON."

    assert "symbol_name" in data, "Key 'symbol_name' missing in result.json"
    assert "computation_result" in data, "Key 'computation_result' missing in result.json"
    assert data["symbol_name"] == "sys_asm_calc_expr_v2", f"Expected symbol_name 'sys_asm_calc_expr_v2', got '{data['symbol_name']}'"
    assert data["computation_result"] == 36, f"Expected computation_result 36, got {data['computation_result']}"

    symbol = actual_symbol()
    result = actual_result(symbol)
    assert data["symbol_name"] == symbol
    assert data["computation_result"] == result


def test_nginx_reverse_proxy():
    try:
        status, body = fetch("http://127.0.0.1:8080/")
        assert status == 200, f"Expected HTTP 200, got {status}"
        assert body == "36", f"Expected response body '36', got '{body}'"
    except urllib.error.URLError as e:
        assert False, f"Failed to connect to Nginx on http://127.0.0.1:8080/: {e}"


def test_python_server_direct():
    try:
        status, body = fetch("http://127.0.0.1:9000/")
        assert status == 200, f"Expected HTTP 200, got {status}"
        assert body == "36", f"Expected response body '36', got '{body}'"
    except urllib.error.URLError as e:
        assert False, f"Failed to connect to Python server on http://127.0.0.1:9000/: {e}"


def test_scripts_exist():
    assert os.path.isfile(PARSER), f"{PARSER} is missing"
    assert os.path.isfile(SERVER), f"{SERVER} is missing"


def target_key(node):
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        return ast.unparse(node)
    return None


def assigned_keys(node):
    keys = set()
    for item in ast.walk(node):
        targets = []
        if isinstance(item, (ast.Assign, ast.AnnAssign, ast.AugAssign)):
            targets = item.targets if isinstance(item, ast.Assign) else [item.target]
        for target in targets:
            for child in ast.walk(target):
                key = target_key(child)
                if key:
                    keys.add(key)
    return keys


def compared_keys(node):
    keys = set()
    for item in ast.walk(node):
        if isinstance(item, ast.Compare):
            for child in ast.walk(item):
                key = target_key(child)
                if key:
                    keys.add(key)
    return keys


def test_parser_executes_nm_and_uses_state_machine():
    source = open(PARSER, "r").read()
    tree = ast.parse(source, PARSER)

    loops = [n for n in ast.walk(tree) if isinstance(n, (ast.For, ast.While))]
    assert loops, "parser.py must parse nm output line by line"
    all_assignments = assigned_keys(tree)
    state_machine_found = False
    for loop in loops:
        loop_assignments = assigned_keys(loop)
        loop_comparisons = compared_keys(loop)
        if any(isinstance(n, ast.If) for n in ast.walk(loop)) and (loop_assignments & loop_comparisons & all_assignments):
            state_machine_found = True
            break
    assert state_machine_found, "parser.py does not contain a state variable tested and transitioned while parsing"

    audit_log = "/tmp/parser_subprocess_audit.json"
    wrapper = r'''
import atexit, json, os, runpy
seen = []
def hook(event, args):
    if event == "subprocess.Popen":
        seen.append(repr(args))
sys_path = os.environ["PARSER_PATH"]
import sys
sys.addaudithook(hook)
@atexit.register
def save():
    with open(os.environ["AUDIT_LOG"], "w") as f:
        json.dump(seen, f)
runpy.run_path(sys_path, run_name="__main__")
'''
    env = os.environ.copy()
    env["PARSER_PATH"] = PARSER
    env["AUDIT_LOG"] = audit_log
    completed = subprocess.run([sys.executable, "-c", wrapper], cwd=PROJECT, env=env,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=8)
    assert completed.returncode == 0, f"parser.py failed when executed: {completed.stderr}"
    assert os.path.isfile(audit_log), "Could not audit parser.py subprocess execution"
    events = " ".join(json.load(open(audit_log)))
    assert "nm" in events and "-D" in events and LIB in events, \
        "parser.py must execute nm -D /home/user/project/libcalc.so"


def test_server_uses_ctypes_binding():
    source = open(SERVER, "r").read()
    tree = ast.parse(source, SERVER)
    imported_ctypes = any(
        (isinstance(n, ast.Import) and any(a.name == "ctypes" for a in n.names)) or
        (isinstance(n, ast.ImportFrom) and n.module == "ctypes")
        for n in ast.walk(tree)
    )
    assert imported_ctypes, "server.py must import ctypes"

    calls = [n for n in ast.walk(tree) if isinstance(n, ast.Call)]
    assert any(
        (isinstance(c.func, ast.Attribute) and c.func.attr == "CDLL") or
        (isinstance(c.func, ast.Name) and c.func.id == "CDLL")
        for c in calls
    ), "server.py must load the shared library with ctypes.CDLL"
    assert LIB in source, f"server.py must load {LIB}"

    assigned_attrs = {
        n.targets[0].attr
        for n in ast.walk(tree)
        if isinstance(n, ast.Assign) and len(n.targets) == 1 and isinstance(n.targets[0], ast.Attribute)
    }
    assert "argtypes" in assigned_attrs, "server.py must set the C function argtypes"
    assert "restype" in assigned_attrs, "server.py must set the C function restype"
    assert "c_int" in source, "server.py must use ctypes.c_int for the int signature"


def test_nginx_configuration_is_real_proxy():
    completed = subprocess.run(["nginx", "-T"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               text=True, timeout=8)
    assert completed.returncode == 0, f"nginx configuration is invalid:\n{completed.stdout}"
    config = completed.stdout
    assert re.search(r"listen\s+127\.0\.0\.1:8080(?:\s|;)", config), \
        "Nginx is not configured to listen on 127.0.0.1:8080"
    assert re.search(r"proxy_pass\s+http://127\.0\.0\.1:9000(?:/)?\s*;", config), \
        "Nginx is not configured to proxy to 127.0.0.1:9000"

    nginx_process = False
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            cmd = open(f"/proc/{name}/cmdline", "rb").read().replace(b"\0", b" ")
            if b"nginx" in cmd:
                nginx_process = True
                break
        except OSError:
            pass
    assert nginx_process, "No running Nginx process was found"


def kill_project_servers():
    victims = []
    for name in os.listdir("/proc"):
        if not name.isdigit() or int(name) == os.getpid():
            continue
        try:
            cmd = open(f"/proc/{name}/cmdline", "rb").read().replace(b"\0", b" ").decode(errors="ignore")
            cwd = os.readlink(f"/proc/{name}/cwd")
            if "server.py" in cmd and (PROJECT in cmd or cwd == PROJECT):
                victims.append(int(name))
        except OSError:
            pass
    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.5)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def wait_fetch(url, expected, timeout=8):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        try:
            status, body = fetch(url, timeout=1)
            if status == 200 and body == str(expected):
                return
            last = f"status={status}, body={body!r}"
        except Exception as exc:
            last = repr(exc)
        time.sleep(0.15)
    assert False, f"Timed out waiting for {url} to return {expected}; last result: {last}"


def test_server_calls_library_for_each_request_and_proxy_forwards():
    symbol = actual_symbol()
    assert re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", symbol), "Exported symbol cannot be used for probe"
    backup = "/tmp/libcalc.original.so"
    probe_file = "/tmp/libcalc_probe_value"
    probe_source = "/tmp/libcalc_probe.c"
    probe_library = "/tmp/libcalc_probe.so"
    shutil.copy2(LIB, backup)
    multiplier = random.SystemRandom().randint(700, 1700)
    first = random.SystemRandom().randint(20000, 50000)
    second = first + random.SystemRandom().randint(1000, 5000)
    base = 5 * multiplier + 7
    process = None

    c_source = f'''#include <stdio.h>\nint {symbol}(int a, int b) {{\n    int probe = -999999;\n    FILE *f = fopen("{probe_file}", "r");\n    if (f) {{ fscanf(f, "%d", &probe); fclose(f); }}\n    return probe + a * {multiplier} + b;\n}}\n'''
    try:
        open(probe_source, "w").write(c_source)
        subprocess.run(["gcc", "-shared", "-fPIC", "-o", probe_library, probe_source], check=True)
        kill_project_servers()
        os.replace(probe_library, LIB)
        open(probe_file, "w").write(str(first))
        process = subprocess.Popen([sys.executable, SERVER], cwd=PROJECT,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        wait_fetch("http://127.0.0.1:9000/", first + base)
        open(probe_file, "w").write(str(second))
        wait_fetch("http://127.0.0.1:8080/", second + base)

        third = second + random.SystemRandom().randint(1000, 5000)
        open(probe_file, "w").write(str(third))
        wait_fetch("http://127.0.0.1:9000/", third + base)
    finally:
        kill_project_servers()
        if os.path.exists(backup):
            os.replace(backup, LIB)
        for path in (probe_file, probe_source, probe_library):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
        try:
            subprocess.Popen([sys.executable, SERVER], cwd=PROJECT,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
