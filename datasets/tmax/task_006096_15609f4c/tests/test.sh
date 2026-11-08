#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import re
import secrets
import shutil
import subprocess
import sys
import textwrap
import urllib.parse
import urllib.request

import pytest

ROOT = "/home/user/migration"
SO_PATH = f"{ROOT}/rust_ext/target/release/librust_ext.so"
APP_PATH = f"{ROOT}/app.py"
CONF_PATH = f"{ROOT}/nginx.conf"


def test_final_output_log():
    log_path = f"{ROOT}/final_output.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."
    with open(log_path, "r") as f:
        content = f.read().strip()
    assert content == "noitargim", f"Expected 'noitargim' in {log_path}, but got '{content}'"


def test_rust_so_exists():
    assert os.path.isfile(SO_PATH), f"Rust shared library {SO_PATH} does not exist. Did you run cargo build --release?"


def test_app_py_migrated():
    assert os.path.isfile(APP_PATH), f"Python 3 app file {APP_PATH} does not exist."
    with open(APP_PATH, "r") as f:
        content = f.read()
    assert "BaseHTTPServer" not in content, "BaseHTTPServer is still in app.py, so it was not properly migrated to Python 3."
    assert "ctypes" in content, "ctypes not found in app.py. FFI integration is missing."


def test_rust_lib_rs_fixed():
    lib_rs = f"{ROOT}/rust_ext/src/lib.rs"
    assert os.path.isfile(lib_rs), f"Rust source file {lib_rs} does not exist."
    with open(lib_rs, "r") as f:
        content = f.read()
    assert "into_raw" in content, "The Rust code does not seem to use into_raw() to prevent the dangling pointer."


def test_rust_project_rebuilds_and_export_works():
    project = f"{ROOT}/rust_ext"
    subprocess.run(["cargo", "clean"], cwd=project, check=True, capture_output=True, text=True, timeout=60)
    built = subprocess.run(
        ["cargo", "build", "--release"], cwd=project,
        capture_output=True, text=True, timeout=180
    )
    assert built.returncode == 0, f"cargo build --release failed:\n{built.stdout}\n{built.stderr}"
    assert os.path.isfile(SO_PATH)

    try:
        lib = ctypes.CDLL(SO_PATH)
        fn = lib.reverse_string
    except Exception as exc:
        pytest.fail(f"Could not load reverse_string from the built shared library: {exc}")
    fn.argtypes = [ctypes.c_char_p]
    fn.restype = ctypes.c_void_p

    samples = [
        "ffi-" + secrets.token_hex(12),
        secrets.token_urlsafe(31),
        "mañana-🙂-" + secrets.token_hex(5),
        "",
    ]
    for value in samples:
        ptr = fn(value.encode("utf-8"))
        assert ptr, f"reverse_string returned a null pointer for {value!r}"
        actual = ctypes.string_at(ptr).decode("utf-8")
        assert actual == value[::-1], f"Rust FFI returned {actual!r}, expected {value[::-1]!r}"


def test_real_app_wrapper_uses_the_shared_library():
    # Temporarily put a probe library at the required path. A fresh import of app.py
    # must return the probe's marker, proving its wrapper actually invokes the FFI.
    probe_src = "/tmp/rust_ffi_probe.rs"
    probe_so = "/tmp/librust_ffi_probe.so"
    backup = SO_PATH + ".verifier-backup"
    with open(probe_src, "w") as f:
        f.write(textwrap.dedent(r'''
            use std::os::raw::c_char;
            #[no_mangle]
            pub extern "C" fn reverse_string(_: *const c_char) -> *const c_char {
                b"ffi_probe_marker\0".as_ptr() as *const c_char
            }
        '''))
    compiled = subprocess.run(
        ["rustc", "--crate-type", "cdylib", "-O", probe_src, "-o", probe_so],
        capture_output=True, text=True, timeout=120
    )
    assert compiled.returncode == 0, f"Could not compile verifier probe library:\n{compiled.stdout}\n{compiled.stderr}"

    if os.path.exists(backup):
        os.unlink(backup)
    os.replace(SO_PATH, backup)
    try:
        shutil.copy2(probe_so, SO_PATH)
        probe_code = textwrap.dedent(f'''
            import importlib.util
            spec = importlib.util.spec_from_file_location("submitted_app", {APP_PATH!r})
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            assert hasattr(module, "reverse_string"), "app.py has no reverse_string wrapper"
            result = module.reverse_string("this must not be reversed in Python")
            if isinstance(result, bytes):
                result = result.decode("utf-8")
            assert result == "ffi_probe_marker", repr(result)
        ''')
        result = subprocess.run(
            [sys.executable, "-c", probe_code], cwd=ROOT,
            capture_output=True, text=True, timeout=20
        )
        assert result.returncode == 0, (
            "Importing app.py and calling reverse_string did not invoke the shared library.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
    finally:
        if os.path.exists(SO_PATH):
            os.unlink(SO_PATH)
        os.replace(backup, SO_PATH)


def _processes():
    found = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            with open(f"/proc/{name}/cmdline", "rb") as f:
                cmdline = f.read().replace(b"\0", b" ").decode(errors="replace")
            exe = os.path.realpath(f"/proc/{name}/exe")
            with open(f"/proc/{name}/status", "r") as f:
                status = f.read()
            ppid = int(re.search(r"^PPid:\s+(\d+)", status, re.M).group(1))
            uid = int(re.search(r"^Uid:\s+(\d+)", status, re.M).group(1))
            found.append((int(name), ppid, uid, exe, cmdline))
        except (FileNotFoundError, PermissionError, AttributeError, ValueError):
            pass
    return found


def test_nginx_running():
    assert os.path.isfile(CONF_PATH), f"Nginx config {CONF_PATH} does not exist."

    result = subprocess.run(["ps", "aux"], capture_output=True, text=True)
    assert "nginx" in result.stdout and CONF_PATH in result.stdout, "Nginx does not appear to be running with the specified config."

    processes = _processes()
    masters = [p for p in processes if os.path.basename(p[3]) == "nginx" and CONF_PATH in p[4]]
    assert masters, "No real nginx process is running with the required configuration path."
    master_pids = {p[0] for p in masters}
    workers = [p for p in processes if os.path.basename(p[3]) == "nginx" and p[1] in master_pids]
    assert workers, "The configured nginx master has no running worker process."
    assert any(p[2] != 0 for p in workers), "Nginx workers are running as root rather than a non-root user."

    checked = subprocess.run(["nginx", "-t", "-c", CONF_PATH], capture_output=True, text=True, timeout=20)
    assert checked.returncode == 0, f"nginx configuration is invalid:\n{checked.stdout}\n{checked.stderr}"
    dumped = subprocess.run(["nginx", "-T", "-c", CONF_PATH], capture_output=True, text=True, timeout=20)
    assert dumped.returncode == 0, f"Could not inspect nginx configuration:\n{dumped.stdout}\n{dumped.stderr}"
    config = dumped.stdout + "\n" + dumped.stderr
    assert re.search(r"\blisten\s+127\.0\.0\.1:8080\b", config), "nginx does not listen on 127.0.0.1:8080."
    assert re.search(r"\bproxy_pass\s+http://127\.0\.0\.1:8000\s*;", config), "nginx does not proxy to 127.0.0.1:8000."
    user_match = re.search(r"(?m)^\s*user\s+([^;\s]+)", config)
    assert user_match and user_match.group(1) != "root", "nginx is not configured with a non-root user."
    pid_match = re.search(r"(?m)^\s*pid\s+([^;]+);", config)
    assert pid_match, "nginx.conf must set a writable non-default pid path."
    pid_path = pid_match.group(1).strip()
    assert not pid_path.startswith(("/run/", "/var/run/")), "nginx uses a root-owned default pid location."
    assert "/var/log/nginx" not in config, "nginx uses root-owned default log paths."


def test_python_app_running():
    result = subprocess.run(["ps", "aux"], capture_output=True, text=True)
    assert "app.py" in result.stdout and "python" in result.stdout.lower(), "app.py does not appear to be running in the background."

    real = [
        p for p in _processes()
        if "python" in os.path.basename(p[3]).lower() and APP_PATH in p[4]
    ]
    assert real, "No real Python interpreter is running /home/user/migration/app.py."


def test_requests_reach_nginx_and_return_dynamic_ffi_results():
    samples = [
        "proxy-" + secrets.token_hex(16),
        secrets.token_urlsafe(37),
        "Rust与Python🙂-" + secrets.token_hex(4),
    ]
    for value in samples:
        query = urllib.parse.urlencode({"text": value})
        url = "http://127.0.0.1:8080/?" + query
        with urllib.request.urlopen(url, timeout=10) as response:
            body = response.read().decode("utf-8")
            assert response.status == 200
        assert body == value[::-1], f"Proxy returned {body!r}, expected {value[::-1]!r} for {value!r}"

    with urllib.request.urlopen("http://127.0.0.1:8080/", timeout=10) as response:
        assert response.status == 200
        assert response.read().decode("utf-8") == ""


def test_pytest_file_passes():
    test_file = f"{ROOT}/test_app.py"
    assert os.path.isfile(test_file), f"Pytest file {test_file} does not exist."

    result = subprocess.run(
        ["pytest", test_file], cwd=ROOT, capture_output=True, text=True, timeout=120
    )
    assert result.returncode == 0, f"pytest {test_file} failed. Output:\n{result.stdout}\n{result.stderr}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
