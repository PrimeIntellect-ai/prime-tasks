#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import hashlib
import json
import os
import re
import secrets
import shutil
import signal
import subprocess
import time
import urllib.error
import urllib.request

import pytest

PROJECT = "/home/user/sanitizer_project"
APP_DIR = "/home/user/app"
LIB_PATH = "/home/user/app/libsans.so"
EVIL_DIR = "/home/user/data/evil"
CLEAN_DIR = "/home/user/data/clean"
URL = "http://localhost:5000/submit"


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.digest()


def stop_existing_services():
    if shutil.which("fuser"):
        subprocess.run(["fuser", "-k", "5000/tcp"], stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, check=False)
    else:
        for entry in os.listdir("/proc"):
            if not entry.isdigit() or int(entry) == os.getpid():
                continue
            try:
                with open(f"/proc/{entry}/cmdline", "rb") as f:
                    cmdline = f.read().replace(b"\0", b" ")
                if b"/home/user/app/app.py" in cmdline:
                    os.kill(int(entry), signal.SIGTERM)
            except (FileNotFoundError, ProcessLookupError, PermissionError):
                pass
    subprocess.run(["redis-cli", "-p", "6379", "shutdown", "nosave"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    time.sleep(1)


def check_payload(text):
    data = json.dumps({"text": text}).encode("utf-8")
    req = urllib.request.Request(URL, data=data, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            return response.status
    except urllib.error.HTTPError as e:
        return e.code
    except Exception:
        return None


def wait_for_service():
    deadline = time.time() + 12
    while time.time() < deadline:
        status = check_payload("verifier startup " + secrets.token_hex(8))
        if status == 200:
            return
        time.sleep(0.25)
    pytest.fail("Flask service did not become ready on port 5000")


@pytest.fixture(scope="session", autouse=True)
def setup_services():
    assert os.path.isdir(PROJECT), "Rust project is missing"
    cargo_toml = os.path.join(PROJECT, "Cargo.toml")
    assert os.path.isfile(cargo_toml), "Cargo.toml is missing"

    metadata_run = subprocess.run(
        ["cargo", "metadata", "--no-deps", "--format-version", "1"],
        cwd=PROJECT, text=True, capture_output=True, timeout=60
    )
    assert metadata_run.returncode == 0, metadata_run.stderr
    metadata = json.loads(metadata_run.stdout)
    cdylib_targets = [
        target for package in metadata["packages"] for target in package["targets"]
        if "cdylib" in target.get("crate_types", [])
    ]
    assert cdylib_targets, "Cargo project does not define a cdylib target"

    rust_sources = []
    for root, dirs, files in os.walk(PROJECT):
        dirs[:] = [d for d in dirs if d != "target"]
        rust_sources.extend(os.path.join(root, f) for f in files if f.endswith(".rs"))
    assert rust_sources, "Rust source files are missing"
    assert any("is_clean" in open(p, encoding="utf-8").read() for p in rust_sources), \
        "Rust source does not implement is_clean"

    build_script = os.path.join(APP_DIR, "build.sh")
    assert os.path.isfile(build_script), "build.sh is missing"
    subprocess.run(["cargo", "clean"], cwd=PROJECT, check=True, timeout=60)
    try:
        os.unlink(LIB_PATH)
    except FileNotFoundError:
        pass
    build = subprocess.run(["bash", build_script], cwd=APP_DIR, text=True,
                           capture_output=True, timeout=180)
    assert build.returncode == 0, build.stdout + build.stderr
    assert os.path.isfile(LIB_PATH), "build.sh did not create /home/user/app/libsans.so"
    with open(LIB_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "libsans.so is not an ELF shared library"

    target_dir = metadata["target_directory"]
    cargo_libraries = []
    for target in cdylib_targets:
        name = target["name"].replace("-", "_")
        candidate = os.path.join(target_dir, "release", f"lib{name}.so")
        if os.path.isfile(candidate):
            cargo_libraries.append(candidate)
    assert cargo_libraries, "release-mode Cargo cdylib artifact is missing"
    assert any(sha256(p) == sha256(LIB_PATH) for p in cargo_libraries), \
        "libsans.so is not the release cdylib produced by the Rust project"

    symbols = subprocess.run(["nm", "-D", "--defined-only", LIB_PATH], text=True,
                             capture_output=True, timeout=30)
    assert symbols.returncode == 0, symbols.stderr
    assert re.search(r"(?:^|\s)is_clean$", symbols.stdout, re.MULTILINE), \
        "shared library does not export is_clean"

    wrapper_path = os.path.join(APP_DIR, "wrapper.py")
    assert os.path.isfile(wrapper_path), "wrapper.py is missing"
    wrapper_source = open(wrapper_path, encoding="utf-8").read()
    wrapper_tree = ast.parse(wrapper_source)
    assert any(isinstance(n, (ast.Import, ast.ImportFrom)) and
               ((isinstance(n, ast.ImportFrom) and n.module == "ctypes") or
                (isinstance(n, ast.Import) and any(a.name == "ctypes" for a in n.names)))
               for n in ast.walk(wrapper_tree)), "wrapper.py does not import ctypes"
    assert any(isinstance(n, ast.FunctionDef) and n.name == "check_text"
               for n in ast.walk(wrapper_tree)), "wrapper.py does not define check_text"
    assert re.search(r"\b(CDLL|LoadLibrary|cdll)\b", wrapper_source), \
        "wrapper.py does not load a library through ctypes"

    app_source = open(os.path.join(APP_DIR, "app.py"), encoding="utf-8").read()
    app_tree = ast.parse(app_source)
    assert any((isinstance(n, ast.Import) and any(a.name == "wrapper" for a in n.names)) or
               (isinstance(n, ast.ImportFrom) and n.module == "wrapper")
               for n in ast.walk(app_tree)), "Flask application does not import wrapper"
    assert "check_text" in app_source, "Flask application does not use check_text"

    config_path = os.path.join(APP_DIR, "config.env")
    assert os.path.isfile(config_path), "config.env is missing"
    config = open(config_path, encoding="utf-8").read()
    assert re.search(r"(?m)^\s*(?:export\s+)?REDIS_URL\s*=\s*['\"]?redis://localhost:6379['\"]?\s*$", config)
    assert re.search(r"(?m)^\s*(?:export\s+)?SAN_LIB_PATH\s*=\s*['\"]?/home/user/app/libsans\.so['\"]?\s*$", config)

    stop_existing_services()
    start_script = os.path.join(APP_DIR, "start.sh")
    assert os.path.isfile(start_script), "start.sh is missing"
    started = subprocess.run(["bash", start_script], cwd=APP_DIR, text=True,
                             capture_output=True, timeout=20)
    assert started.returncode == 0, started.stdout + started.stderr
    wait_for_service()
    pong = subprocess.run(["redis-cli", "-p", "6379", "ping"], text=True,
                          capture_output=True, timeout=10)
    assert pong.returncode == 0 and pong.stdout.strip() == "PONG", "Redis is not running"
    subprocess.run(["redis-cli", "-p", "6379", "flushall"], check=True,
                   stdout=subprocess.DEVNULL, timeout=10)


def test_native_abi_and_python_wrapper_on_unseen_inputs():
    token = secrets.token_hex(16)
    cases = [
        (f"ordinary unseen text {token}", True),
        (f"prefix <ScRiPt> suffix {token}", False),
        (f"{token} JaVaScRiPt:alert(1)", False),
        (f"account {token} UnIoN SeLeCt name", False),
        (f"safe mention of script and union {token}", True),
    ]

    native_code = r'''
import ctypes, json, sys
lib = ctypes.CDLL("/home/user/app/libsans.so")
fn = lib.is_clean
fn.argtypes = [ctypes.c_char_p]
fn.restype = ctypes.c_bool
cases = json.load(sys.stdin)
for text, expected in cases:
    got = bool(fn(text.encode("utf-8")))
    if got != expected:
        raise SystemExit(f"native mismatch for {text!r}: {got} != {expected}")
# A null pointer must be handled without crossing the FFI boundary with a crash.
fn(None)
'''
    native = subprocess.run(["python3", "-c", native_code], input=json.dumps(cases),
                            text=True, capture_output=True, timeout=30)
    assert native.returncode == 0, native.stdout + native.stderr

    wrapper_code = r'''
import json, sys
sys.path.insert(0, "/home/user/app")
import wrapper
for text, expected in json.load(sys.stdin):
    got = wrapper.check_text(text)
    if type(got) is not bool or got != expected:
        raise SystemExit(f"wrapper mismatch for {text!r}: {got!r} != {expected}")
'''
    env = os.environ.copy()
    env["SAN_LIB_PATH"] = LIB_PATH
    wrapped = subprocess.run(["python3", "-c", wrapper_code], input=json.dumps(cases),
                             text=True, capture_output=True, env=env, timeout=30)
    assert wrapped.returncode == 0, wrapped.stdout + wrapped.stderr

    for text, expected in cases:
        assert check_payload(text) == (200 if expected else 403)


def test_adversarial_corpus():
    assert os.path.isdir(EVIL_DIR), f"Directory {EVIL_DIR} is missing"
    assert os.path.isdir(CLEAN_DIR), f"Directory {CLEAN_DIR} is missing"

    evil_files = sorted(f for f in os.listdir(EVIL_DIR)
                        if os.path.isfile(os.path.join(EVIL_DIR, f)))
    clean_files = sorted(f for f in os.listdir(CLEAN_DIR)
                         if os.path.isfile(os.path.join(CLEAN_DIR, f)))
    assert len(evil_files) > 0, "No evil files found to test."
    assert len(clean_files) > 0, "No clean files found to test."

    evil_bypassed = []
    clean_modified = []
    for f in evil_files:
        with open(os.path.join(EVIL_DIR, f), encoding="utf-8") as file:
            content = file.read()
        if check_payload(content) != 403:
            evil_bypassed.append(f)
    for f in clean_files:
        with open(os.path.join(CLEAN_DIR, f), encoding="utf-8") as file:
            content = file.read()
        if check_payload(content) != 200:
            clean_modified.append(f)

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: " +
                      ", ".join(evil_bypassed[:10]))
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: " +
                      ", ".join(clean_modified[:10]))
    if errors:
        pytest.fail("\n".join(errors))


def test_additional_unseen_http_payloads():
    token = secrets.token_hex(20)
    clean = [
        f"A newly generated harmless sentence {token}",
        f"The words union and select are separate here: union value {token} select",
        f"Angle brackets without the forbidden token <safe>{token}</safe>",
        f"A URL using https://example.invalid/{token}",
    ]
    evil = [
        f"{token}<script>new payload</script>",
        f"before {token} JAVASCRIPT:confirm(1)",
        f"query {token} UNION SELECT secret FROM table",
        f"mixed <sCrIpT> {token}",
        f"mixed uNiOn SeLeCt {token}",
    ]
    for text in clean:
        assert check_payload(text) == 200, f"unseen clean payload rejected: {text!r}"
    for text in evil:
        assert check_payload(text) == 403, f"unseen evil payload accepted: {text!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
