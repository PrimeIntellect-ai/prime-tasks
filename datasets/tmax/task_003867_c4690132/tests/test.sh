#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import importlib.machinery
import importlib.util
import inspect
import json
import os
import secrets
import subprocess
import sys
import xml.etree.ElementTree as ET

import pytest

WORKSPACE_DIR = "/home/user/workspace"
C_DIR = os.path.join(WORKSPACE_DIR, "c_src")
PKG_DIR = os.path.join(WORKSPACE_DIR, "python_pkg")
TESTS_DIR = os.path.join(WORKSPACE_DIR, "tests")
EXPECTED_PAYLOADS = [
    {"id": 1, "payload": "<script>alert(1)</script>"},
    {"id": 2, "payload": "<img src=x onerror=alert(1)>"},
    {"id": 3, "payload": "javascript:eval('alert(1)')"},
]


def expected_sanitize(value):
    return value.replace("eval(", "SAFE_").replace("onerror", "onsafe ")


def load_payloads_module():
    payloads_path = os.path.join(TESTS_DIR, "payloads.py")
    spec = importlib.util.spec_from_file_location("payloads", payloads_path)
    module = importlib.util.module_from_spec(spec)
    sys.modules["payloads"] = module
    spec.loader.exec_module(module)
    return module


def test_c_library_built():
    so_path = os.path.join(C_DIR, "libhtmlparser.so")
    assert os.path.isfile(so_path), f"C library was not built at {so_path}"
    with open(so_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "libhtmlparser.so is not an ELF shared library"

    source_path = os.path.join(C_DIR, "htmlparser.c")
    with open(source_path, "r") as f:
        source = f.read()
    assert "VULNERABLE: Does nothing" not in source, "security_fix.patch was not applied"
    assert 'strstr(output, "eval(")' in source
    assert 'strstr(output, "onerror")' in source
    assert 'strncpy(match, "SAFE_", 5)' in source
    assert 'strncpy(match, "onsafe ", 7)' in source

    lib = ctypes.CDLL(so_path)
    sanitize = lib.sanitize
    sanitize.argtypes = [ctypes.c_char_p]
    sanitize.restype = ctypes.c_void_p
    libc = ctypes.CDLL(None)
    libc.free.argtypes = [ctypes.c_void_p]

    nonce = secrets.token_hex(12)
    samples = [
        f"prefix-{nonce}-eval(7)-suffix",
        f"<img {nonce} onerror=eval(9)>",
        f"onerror-{nonce}-onerror-eval(1)-eval(2)",
        f"plain-{nonce}",
    ]
    for sample in samples:
        ptr = sanitize(sample.encode("ascii"))
        assert ptr, "C sanitize returned NULL"
        try:
            actual = ctypes.string_at(ptr).decode("ascii")
        finally:
            libc.free(ptr)
        assert actual == expected_sanitize(sample), f"C library sanitized {sample!r} incorrectly"


def test_setup_configuration():
    setup_path = os.path.join(PKG_DIR, "setup.py")
    assert os.path.isfile(setup_path), "python_pkg/setup.py is missing"
    probe = r'''
import json, runpy, setuptools
captured = {}
def fake_setup(*args, **kwargs):
    captured.update(kwargs)
setuptools.setup = fake_setup
runpy.run_path(%r, run_name="__main__")
exts = captured.get("ext_modules", [])
assert exts
ext = exts[0]
print(json.dumps({
    "include_dirs": list(ext.include_dirs or []),
    "library_dirs": list(ext.library_dirs or []),
    "runtime_library_dirs": list(ext.runtime_library_dirs or []),
    "libraries": list(ext.libraries or []),
}))
''' % setup_path
    proc = subprocess.run(
        [sys.executable, "-c", probe], cwd=PKG_DIR,
        text=True, capture_output=True, timeout=20
    )
    assert proc.returncode == 0, f"Could not inspect setup.py: {proc.stderr}"
    config = json.loads(proc.stdout.strip().splitlines()[-1])
    assert C_DIR in config["include_dirs"], "setup.py include_dirs does not contain the absolute C library path"
    assert C_DIR in config["library_dirs"], "setup.py library_dirs does not contain the absolute C library path"
    assert C_DIR in config["runtime_library_dirs"], "setup.py runtime_library_dirs does not contain the absolute C library path"
    assert "htmlparser" in config["libraries"], "setup.py does not link against htmlparser"


def test_python_package_installed():
    try:
        import fast_sanitizer
    except ImportError:
        pytest.fail("fast_sanitizer package is not installed or importable.")

    module_path = os.path.realpath(fast_sanitizer.__file__)
    assert any(module_path.endswith(suffix) for suffix in importlib.machinery.EXTENSION_SUFFIXES), \
        "fast_sanitizer is not a compiled Python extension"
    assert os.path.commonpath([module_path, PKG_DIR]) == PKG_DIR, \
        "fast_sanitizer was not built from python_pkg"
    assert inspect.isbuiltin(fast_sanitizer.sanitize), "sanitize is not provided by the compiled extension"

    dynamic = subprocess.run(["readelf", "-d", module_path], text=True, capture_output=True, timeout=20)
    assert dynamic.returncode == 0, f"Could not inspect extension linkage: {dynamic.stderr}"
    assert "libhtmlparser.so" in dynamic.stdout, "Extension does not dynamically link libhtmlparser.so"
    assert C_DIR in dynamic.stdout, "Extension does not contain the required runtime library directory"

    linked = subprocess.run(["ldd", module_path], text=True, capture_output=True, timeout=20)
    assert linked.returncode == 0, f"Could not resolve extension dependencies: {linked.stderr}"
    assert os.path.join(C_DIR, "libhtmlparser.so") in linked.stdout, \
        "Extension does not resolve libhtmlparser.so from /home/user/workspace/c_src"

    # Preserve the original patched-library assertion.
    try:
        res = fast_sanitizer.sanitize("eval(1)")
        assert "SAFE_" in res, "The C library does not seem to be patched correctly."
    except Exception as e:
        pytest.fail(f"fast_sanitizer.sanitize failed: {e}")

    nonce = secrets.token_hex(16)
    for value in [
        f"A-{nonce}-eval(123)-B",
        f"<tag onerror={nonce}>",
        f"eval(1)-onerror-eval(2)-{nonce}",
        f"unchanged-{nonce}",
    ]:
        assert fast_sanitizer.sanitize(value) == expected_sanitize(value)


def test_payloads_py_exists_and_correct():
    payloads_path = os.path.join(TESTS_DIR, "payloads.py")
    assert os.path.isfile(payloads_path), f"File {payloads_path} is missing."

    try:
        payloads = load_payloads_module()
    except Exception as e:
        pytest.fail(f"Failed to execute payloads.py: {e}")

    assert hasattr(payloads, "get_payloads"), "get_payloads function missing in payloads.py"
    data = payloads.get_payloads()
    assert isinstance(data, list), "get_payloads should return a list"
    assert len(data) == 3, "get_payloads should return exactly 3 items"
    assert data[0].get("id") == 1, "First payload ID should be 1"
    assert data[0].get("payload") == "<script>alert(1)</script>", "First payload string mismatch"
    assert data == EXPECTED_PAYLOADS, "payloads.py does not exactly translate all payloads from payloads.js"


def test_integration_runner_executes_and_generates_xml():
    xml_path = os.path.join(TESTS_DIR, "results.xml")
    if os.path.exists(xml_path):
        os.remove(xml_path)

    proc = subprocess.run(
        [sys.executable, os.path.join(TESTS_DIR, "test_runner.py")],
        cwd=TESTS_DIR, text=True, capture_output=True, timeout=30
    )
    assert proc.returncode == 0, f"test_runner.py failed:\nstdout: {proc.stdout}\nstderr: {proc.stderr}"
    assert os.path.isfile(xml_path), "test_runner.py did not generate results.xml"

    root = ET.parse(xml_path).getroot()
    rows = root.findall("Result")
    assert len(rows) == len(EXPECTED_PAYLOADS), "results.xml has the wrong number of Result elements"

    import fast_sanitizer
    for row, payload in zip(rows, EXPECTED_PAYLOADS):
        assert row.findtext("ID") == str(payload["id"])
        assert row.findtext("Original") == payload["payload"]
        assert row.findtext("Sanitized") == fast_sanitizer.sanitize(payload["payload"])


def test_results_xml_exists():
    xml_path = os.path.join(TESTS_DIR, "results.xml")
    assert os.path.isfile(xml_path), f"XML results file {xml_path} is missing."


def test_summary_json_correct():
    json_path = os.path.join(WORKSPACE_DIR, "summary.json")
    assert os.path.isfile(json_path), f"JSON summary file {json_path} is missing."

    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("summary.json is not valid JSON.")

    assert isinstance(data, list), "summary.json should contain a JSON array."
    assert len(data) == 3, "summary.json should have exactly 3 entries."

    expected_data = [
        {"id": 1, "original": "<script>alert(1)</script>", "sanitized": "<script>alert(1)</script>", "is_safe": False},
        {"id": 2, "original": "<img src=x onerror=alert(1)>", "sanitized": "<img src=x onsafe =alert(1)>", "is_safe": True},
        {"id": 3, "original": "javascript:eval('alert(1)')", "sanitized": "javascript:SAFE_('alert(1)')", "is_safe": True},
    ]

    for i, expected in enumerate(expected_data):
        assert data[i].get("id") == expected["id"], f"Item {i} 'id' mismatch. Expected {expected['id']}, got {data[i].get('id')}."
        assert data[i].get("original") == expected["original"], f"Item {i} 'original' mismatch."
        assert data[i].get("sanitized") == expected["sanitized"], f"Item {i} 'sanitized' mismatch."
        assert data[i].get("is_safe") is expected["is_safe"], f"Item {i} 'is_safe' mismatch. Expected {expected['is_safe']}, got {data[i].get('is_safe')}."
        assert set(data[i]) == {"id", "original", "sanitized", "is_safe"}, f"Item {i} has an invalid structure."

    root = ET.parse(os.path.join(TESTS_DIR, "results.xml")).getroot()
    rows = root.findall("Result")
    assert len(rows) == len(data)
    for item, row in zip(data, rows):
        assert item["id"] == int(row.findtext("ID"))
        assert item["original"] == row.findtext("Original")
        assert item["sanitized"] == row.findtext("Sanitized")
        assert item["is_safe"] is ("<script>" not in row.findtext("Sanitized"))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
