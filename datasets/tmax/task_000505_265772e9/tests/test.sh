#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import importlib.machinery
import importlib.util
import os
import random
import re
import shutil
import subprocess
import sys

import pytest

APP_DIR = "/home/user/app"
RESULTS_FILE = os.path.join(APP_DIR, "results.txt")
MAIN_FILE = os.path.join(APP_DIR, "main.py")
SETUP_FILE = os.path.join(APP_DIR, "setup.py")
STREAM_LOG = os.path.join(APP_DIR, "stream.log")
LEGACY_LIB = os.path.join(APP_DIR, "legacy", "libprocessor.so")


def run(cmd, **kwargs):
    return subprocess.run(cmd, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, **kwargs)


def execute_main():
    env = os.environ.copy()
    env.pop("LD_LIBRARY_PATH", None)
    proc = run([sys.executable, MAIN_FILE], cwd=APP_DIR, env=env)
    assert proc.returncode == 0, f"main.py failed:\n{proc.stdout}"
    assert os.path.isfile(RESULTS_FILE), f"{RESULTS_FILE} was not created."


def parse_blocks(path):
    accepted = []
    counts = {}
    current_ip = None
    payload = []
    with open(path, "r", newline="") as f:
        for raw in f:
            line = raw.rstrip("\r\n")
            if line.startswith("START "):
                current_ip = line.split(" ", 1)[1]
                payload = []
            elif line.startswith("PAYLOAD:") and current_ip is not None:
                payload.append(line[len("PAYLOAD:"):])
            elif line == "END" and current_ip is not None:
                count = counts.get(current_ip, 0)
                if count < 2:
                    counts[current_ip] = count + 1
                    accepted.append("".join(payload))
                current_ip = None
                payload = []
    return accepted


def test_main_py_exists():
    assert os.path.isfile(MAIN_FILE), f"{MAIN_FILE} does not exist. You must implement the Python script."


def test_setup_py_fixed_and_real_extension():
    assert os.path.isfile(SETUP_FILE), f"{SETUP_FILE} does not exist."
    with open(SETUP_FILE, "r") as f:
        content = f.read()

    # Preserve the original source-level assertion, then validate the resulting ELF.
    has_rpath = "runtime_library_dirs" in content or "-Wl,-rpath" in content
    assert has_rpath, "setup.py does not appear to permanently encode the library path."

    for path in glob.glob(os.path.join(APP_DIR, "_legacy_wrapper*.so")):
        os.remove(path)
    shutil.rmtree(os.path.join(APP_DIR, "build"), ignore_errors=True)

    env = os.environ.copy()
    env.pop("LD_LIBRARY_PATH", None)
    proc = run([sys.executable, "setup.py", "build_ext", "--inplace"],
               cwd=APP_DIR, env=env)
    assert proc.returncode == 0, f"Building the extension failed:\n{proc.stdout}"

    importlib.invalidate_caches()
    sys.path.insert(0, APP_DIR)
    sys.modules.pop("_legacy_wrapper", None)
    spec = importlib.util.find_spec("_legacy_wrapper")
    assert spec is not None and spec.origin, "The built _legacy_wrapper extension was not found."
    assert isinstance(spec.loader, importlib.machinery.ExtensionFileLoader), \
        f"_legacy_wrapper is not a compiled Python extension: {spec.origin}"
    extension_path = os.path.realpath(spec.origin)
    assert os.path.isfile(extension_path)

    dynamic = run(["readelf", "-d", extension_path])
    assert dynamic.returncode == 0, f"Could not inspect extension ELF:\n{dynamic.stdout}"
    assert "libprocessor.so" in dynamic.stdout, \
        "The extension is not dynamically linked to libprocessor.so."
    assert re.search(r"\((?:RPATH|RUNPATH)\)", dynamic.stdout), \
        "The extension has no encoded RPATH/RUNPATH."

    symbols = run(["readelf", "-Ws", extension_path])
    assert symbols.returncode == 0
    assert "process_data" in symbols.stdout and " UND " in symbols.stdout, \
        "The extension does not reference process_data from the legacy library."

    linked = run(["ldd", extension_path], env=env)
    assert linked.returncode == 0, f"ldd failed:\n{linked.stdout}"
    assert os.path.realpath(LEGACY_LIB) in linked.stdout, \
        f"libprocessor.so did not resolve to {LEGACY_LIB} without LD_LIBRARY_PATH:\n{linked.stdout}"

    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    result = module.process("abc")
    assert result == 294, f"Expected _legacy_wrapper.process('abc') to return 294, got {result}"


def test_main_executes_on_original_stream_and_writes_correct_results():
    execute_main()
    expected = [str(sum(ord(c) for c in payload)) for payload in parse_blocks(STREAM_LOG)]
    with open(RESULTS_FILE, "r") as f:
        actual = [line.strip() for line in f if line.strip()]
    assert actual == expected, \
        f"Results in {RESULTS_FILE} do not match the original stream. Expected {expected}, got {actual}"


def test_main_parses_unseen_stream_rate_limits_and_calls_extension(tmp_path):
    original_stream = open(STREAM_LOG, "rb").read()
    original_library = open(LEGACY_LIB, "rb").read()
    library_mode = os.stat(LEGACY_LIB).st_mode

    rng = random.SystemRandom()
    seed = rng.randrange(20000, 90000)
    token = lambda: "".join(rng.choice("ABCDEFGHJKLMNPQRSTUVWXYZ23456789") for _ in range(9))
    a, b, c = "172.31.9.11", "203.0.113.27", "198.51.100.44"
    blocks = [
        (a, [" " + token(), " middle ", token() + "  "]),
        (b, [token()]),
        (a, [token(), " Case Sensitive"]),
        (c, [" leading-space"]),
        (a, ["THIRD-" + token()]),
        (b, [token(), " two"]),
        (a, ["FOURTH-" + token()]),
        (c, [token(), " trailing  "]),
        (b, ["THIRD-IGNORED-" + token()]),
    ]
    lines = []
    for ip, pieces in blocks:
        lines.append(f"START {ip}\n")
        lines.extend(f"PAYLOAD:{piece}\n" for piece in pieces)
        lines.append("END\n")
    generated_stream = "".join(lines)

    replacement_c = tmp_path / "processor.c"
    replacement_so = tmp_path / "libprocessor.so"
    replacement_c.write_text(f'''#include <string.h>\nint process_data(const char *data) {{\n    int out = {seed};\n    for (size_t i = 0; i < strlen(data); ++i)\n        out += (int)(i + 1) * (unsigned char)data[i];\n    return out;\n}}\n''')
    compiled = run(["gcc", "-shared", "-fPIC", "-o", str(replacement_so), str(replacement_c)])
    assert compiled.returncode == 0, f"Could not build instrumented test library:\n{compiled.stdout}"

    try:
        with open(STREAM_LOG, "w", newline="") as f:
            f.write(generated_stream)
        shutil.copyfile(replacement_so, LEGACY_LIB)
        os.chmod(LEGACY_LIB, library_mode)

        execute_main()

        payloads = parse_blocks(STREAM_LOG)
        expected = []
        for payload in payloads:
            value = seed + sum((i + 1) * ord(ch) for i, ch in enumerate(payload))
            expected.append(str(value))

        with open(RESULTS_FILE, "r") as f:
            actual = f.read().splitlines()
        assert actual == expected, \
            "main.py failed on an unseen stream, did not enforce the two-block limit, " \
            f"did not preserve payload text, or did not call the linked extension. Expected {expected}, got {actual}"
    finally:
        with open(STREAM_LOG, "wb") as f:
            f.write(original_stream)
        with open(LEGACY_LIB, "wb") as f:
            f.write(original_library)
        os.chmod(LEGACY_LIB, library_mode)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
