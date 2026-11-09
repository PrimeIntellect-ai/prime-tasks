#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import glob
import importlib.machinery
import json
import os
import random
import re
import subprocess
import sys
import urllib.request

import pytest

WORKSPACE = "/home/user/workspace/token_api"
LIB_PATH = os.path.join(WORKSPACE, "lib", "libcorealgo.so")
OUTPUT_PATH = "/home/user/api_output.json"


def expected_token(seed):
    for _ in range(1000):
        seed = (seed * 13 + 17) % 9973
    return seed


def clean_env():
    env = os.environ.copy()
    env.pop("LD_LIBRARY_PATH", None)
    return env


def readelf_dynamic(path):
    return subprocess.check_output(["readelf", "-d", path], text=True)


def assert_native_extension(path):
    assert os.path.isfile(path), f"Extension artifact {path} does not exist."
    assert any(path.endswith(suffix) for suffix in importlib.machinery.EXTENSION_SUFFIXES), \
        f"token_ext is not a compiled Python extension: {path}"
    header = subprocess.check_output(["readelf", "-h", path], text=True)
    assert "Type:" in header and ("DYN" in header or "Shared object" in header), \
        f"token_ext is not a valid ELF shared object: {path}"

    dynamic = readelf_dynamic(path)
    assert re.search(r"\(NEEDED\).*\[libcorealgo\.so\]", dynamic), \
        "token_ext is not dynamically linked against libcorealgo.so"

    paths = []
    for line in dynamic.splitlines():
        if "(RPATH)" in line or "(RUNPATH)" in line:
            match = re.search(r"\[([^]]*)\]", line)
            if match:
                paths.extend(match.group(1).split(":"))
    assert paths, "token_ext has no RPATH or RUNPATH for libcorealgo.so"

    origin = os.path.dirname(os.path.realpath(path))
    target_dir = os.path.realpath(os.path.dirname(LIB_PATH))
    resolved = []
    for entry in paths:
        entry = entry.replace("${ORIGIN}", origin).replace("$ORIGIN", origin)
        if entry:
            resolved.append(os.path.realpath(entry))
    assert target_dir in resolved, \
        f"token_ext RPATH/RUNPATH does not include {target_dir}: {paths}"


def test_shared_library_exists_and_is_valid():
    assert os.path.isfile(LIB_PATH), f"Shared library {LIB_PATH} does not exist. Did you compile it?"
    header = subprocess.check_output(["readelf", "-h", LIB_PATH], text=True)
    assert "Type:" in header and ("DYN" in header or "Shared object" in header), \
        f"{LIB_PATH} is not a valid compiled ELF shared library."
    symbols = subprocess.check_output(["readelf", "-Ws", LIB_PATH], text=True)
    assert re.search(r"\bsecure_transform\b", symbols), \
        "libcorealgo.so does not export secure_transform"

    library = ctypes.CDLL(LIB_PATH)
    library.secure_transform.argtypes = [ctypes.c_int]
    library.secure_transform.restype = ctypes.c_int
    seeds = [0, 1, 12, 9972] + [random.SystemRandom().randrange(2, 9000) for _ in range(4)]
    for seed in seeds:
        assert library.secure_transform(seed) == expected_token(seed)


def test_api_output_json():
    assert os.path.isfile(OUTPUT_PATH), f"API output file {OUTPUT_PATH} does not exist."
    with open(OUTPUT_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {OUTPUT_PATH} does not contain valid JSON.")

    assert data.get("status") == "success", \
        f"Expected status 'success' in {OUTPUT_PATH}, got {data.get('status')}"
    assert data.get("seed") == 12, \
        f"Expected seed 12 in {OUTPUT_PATH}, got {data.get('seed')}"
    assert data.get("token") == expected_token(12), \
        f"Expected token {expected_token(12)} in {OUTPUT_PATH}, got {data.get('token')}"


def test_setup_builds_linked_extension_with_rpath(tmp_path):
    setup_py = os.path.join(WORKSPACE, "setup.py")
    assert os.path.isfile(setup_py), "setup.py does not exist"
    build_lib = tmp_path / "built"
    build_temp = tmp_path / "temp"
    subprocess.check_call(
        [sys.executable, setup_py, "build_ext", "--force",
         "--build-lib", str(build_lib), "--build-temp", str(build_temp)],
        cwd=WORKSPACE,
        env=clean_env(),
    )
    artifacts = []
    for suffix in importlib.machinery.EXTENSION_SUFFIXES:
        artifacts.extend(glob.glob(str(build_lib / ("token_ext*" + suffix))))
    assert len(artifacts) == 1, f"setup.py did not build exactly one token_ext extension: {artifacts}"
    assert_native_extension(artifacts[0])

    seeds = [3, 12, 41, random.SystemRandom().randrange(100, 9000)]
    code = (
        "import json, token_ext; "
        f"seeds={seeds!r}; "
        "print(json.dumps({'file': token_ext.__file__, "
        "'values': [token_ext.generate_token(x) for x in seeds]}))"
    )
    env = clean_env()
    env["PYTHONPATH"] = str(build_lib)
    result = subprocess.run(
        [sys.executable, "-c", code], cwd=str(build_lib), env=env,
        text=True, capture_output=True, timeout=20
    )
    assert result.returncode == 0, \
        f"Freshly built token_ext could not load without LD_LIBRARY_PATH: {result.stderr}"
    data = json.loads(result.stdout.strip().splitlines()[-1])
    assert os.path.realpath(data["file"]) == os.path.realpath(artifacts[0])
    assert data["values"] == [expected_token(seed) for seed in seeds]


def test_installed_python_module_import_and_rpath():
    seeds = [0, 5, 12, 73, random.SystemRandom().randrange(100, 9000)]
    code = (
        "import json, token_ext; "
        f"seeds={seeds!r}; "
        "print(json.dumps({'file': token_ext.__file__, "
        "'values': [token_ext.generate_token(x) for x in seeds]}))"
    )
    result = subprocess.run(
        [sys.executable, "-c", code], cwd="/tmp", env=clean_env(),
        text=True, capture_output=True, timeout=20
    )
    assert result.returncode == 0, \
        f"Failed to import token_ext without LD_LIBRARY_PATH: {result.stderr}"
    data = json.loads(result.stdout.strip().splitlines()[-1])
    assert_native_extension(data["file"])
    assert data["values"] == [expected_token(seed) for seed in seeds]


def fetch_and_check(seed):
    url = f"http://localhost:8080/generate?seed={seed}"
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, timeout=2) as response:
        assert response.status == 200, f"API returned status {response.status}"
        data = json.loads(response.read().decode("utf-8"))
    assert data.get("status") == "success", "API did not return status 'success'."
    assert data.get("seed") == seed, "API did not return the correct seed."
    assert data.get("token") == expected_token(seed), "API returned an incorrect token."


def test_api_is_running():
    try:
        fetch_and_check(5)
        fetch_and_check(random.SystemRandom().randrange(100, 9000))
    except Exception as e:
        pytest.fail(f"Could not connect to the API on port 8080 or it returned an error. Is app.py running? Error: {e}")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
