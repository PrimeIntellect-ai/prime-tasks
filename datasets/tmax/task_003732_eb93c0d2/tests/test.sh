#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import importlib
import importlib.util
import json
import math
import os
import random
import subprocess
import sys
import time
import types
import urllib.request

import pytest
import redis

APP = "/home/user/app"
BACKEND = os.path.join(APP, "backend")


def test_completion_log():
    log_path = os.path.join(APP, "completion.log")
    assert os.path.isfile(log_path), "completion.log is missing."
    with open(log_path, "r") as f:
        content = f.read().strip()
    assert content == "SYSTEM_READY", f"Expected 'SYSTEM_READY' in completion.log, found '{content}'"


def test_setup_py_fixed_and_extension_builds():
    setup_path = os.path.join(BACKEND, "setup.py")
    assert os.path.isfile(setup_path), "setup.py is missing."
    with open(setup_path, "r") as f:
        content = f.read()
    assert "libraries=['m']" in content.replace('"', "'").replace(" ", ""), \
        "setup.py does not appear to link the math library ('m')."

    subprocess.run(
        [sys.executable, "setup.py", "build_ext", "--inplace", "--force"],
        cwd=BACKEND,
        check=True,
        timeout=90,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    artifacts = glob.glob(os.path.join(BACKEND, "_fast_math*.so"))
    assert artifacts, "Building setup.py did not produce a compiled _fast_math extension."

    sys.path.insert(0, BACKEND)
    try:
        sys.modules.pop("_fast_math", None)
        extension = importlib.import_module("_fast_math")
        assert any(extension.__file__.endswith(suffix) for suffix in importlib.machinery.EXTENSION_SUFFIXES)
        assert extension.identity(1.2345678901234567) == 1.2345678901234567
    finally:
        sys.path.remove(BACKEND)
        sys.modules.pop("_fast_math", None)


def test_inference_py_fixed_and_uses_float64_with_extension():
    inference_path = os.path.join(BACKEND, "inference.py")
    assert os.path.isfile(inference_path), "inference.py is missing."
    with open(inference_path, "r") as f:
        content = f.read()
    assert "float32" not in content, "inference.py still contains the float32 casting bug."

    observed = []
    fake_extension = types.ModuleType("_fast_math")

    def identity(value):
        observed.append(value)
        return float(value)

    fake_extension.identity = identity
    old_extension = sys.modules.get("_fast_math")
    sys.modules["_fast_math"] = fake_extension
    sys.path.insert(0, BACKEND)
    try:
        spec = importlib.util.spec_from_file_location("inference_under_test", inference_path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        value = 1.2345678901234567
        result = module.run_inference({"val": value})
        assert observed, "run_inference did not pass the value to _fast_math.identity."
        assert not isinstance(observed[0], __import__('numpy').float32), \
            "run_inference passed a float32 value to the C extension."
        assert float(observed[0]) == value, "Precision was lost before calling the C extension."
        assert result == value
    finally:
        sys.path.remove(BACKEND)
        if old_extension is None:
            sys.modules.pop("_fast_math", None)
        else:
            sys.modules["_fast_math"] = old_extension


def test_start_services_fixed():
    script_path = os.path.join(APP, "start_services.sh")
    assert os.path.isfile(script_path), "start_services.sh is missing."
    with open(script_path, "r") as f:
        content = f.read()
    assert "REDIS_PORT=6379" in content, \
        "start_services.sh does not have the corrected REDIS_PORT=6379."


def load_sanitiser():
    sanitiser_path = os.path.join(APP, "sanitiser.py")
    assert os.path.isfile(sanitiser_path), "sanitiser.py is missing."
    spec = importlib.util.spec_from_file_location("sanitiser", sanitiser_path)
    sanitiser = importlib.util.module_from_spec(spec)
    sys.modules["sanitiser"] = sanitiser
    spec.loader.exec_module(sanitiser)
    assert hasattr(sanitiser, "clean_payload"), "clean_payload function missing in sanitiser.py"
    return sanitiser.clean_payload


def test_sanitiser_corpus():
    clean_payload = load_sanitiser()

    evil_path = "/home/user/verifier/evil_payloads.json"
    if os.path.isfile(evil_path):
        with open(evil_path, "r") as f:
            try:
                evil_data = json.load(f)
            except json.JSONDecodeError:
                f.seek(0)
                evil_data = [json.loads(line) for line in f if line.strip()]
        if not isinstance(evil_data, list):
            evil_data = [evil_data]
        evil_bypassed = 0
        for payload in evil_data:
            try:
                clean_payload(payload)
                evil_bypassed += 1
            except ValueError:
                pass
            except Exception as exc:
                pytest.fail(f"clean_payload raised unexpected exception on evil payload: {exc}")
        assert evil_bypassed == 0, f"{evil_bypassed} of {len(evil_data)} evil payloads bypassed the sanitiser."

    clean_path = "/home/user/verifier/clean_payloads.json"
    if os.path.isfile(clean_path):
        with open(clean_path, "r") as f:
            try:
                clean_data = json.load(f)
            except json.JSONDecodeError:
                f.seek(0)
                clean_data = [json.loads(line) for line in f if line.strip()]
        if not isinstance(clean_data, list):
            clean_data = [clean_data]
        clean_modified = 0
        for payload in clean_data:
            original = dict(payload)
            try:
                result = clean_payload(payload)
                if result != original:
                    clean_modified += 1
            except ValueError:
                clean_modified += 1
            except Exception as exc:
                pytest.fail(f"clean_payload raised unexpected exception on clean payload: {exc}")
        assert clean_modified == 0, f"{clean_modified} of {len(clean_data)} clean payloads were modified or rejected."


def test_sanitiser_generated_inputs():
    clean_payload = load_sanitiser()
    rng = random.SystemRandom()

    valid_values = [-1e10, 1e10, 0.0, -0.0, 1e-300, -1e-300, "6.25e-120"]
    valid_values.extend(rng.uniform(-1e10, 1e10) for _ in range(30))
    for value in valid_values:
        payload = {"val": value}
        original = dict(payload)
        result = clean_payload(payload)
        assert result == original, f"Valid payload was modified or rejected: {original!r}"

    invalid_values = [
        float("nan"), float("inf"), float("-inf"),
        "NaN", "Infinity", "-Infinity", "not-a-number", "", None,
        1e10 + rng.uniform(1.0, 1e6),
        -1e10 - rng.uniform(1.0, 1e6),
        f"{1e10 + rng.uniform(1.0, 1e6):.17e}",
    ]
    for value in invalid_values:
        with pytest.raises(ValueError):
            clean_payload({"val": value})

    with pytest.raises(ValueError):
        clean_payload({"val": 1.0, "other": "invalid-number"})


def post_json(url, payload):
    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=4) as response:
        assert response.status == 200
        return json.loads(response.read().decode("utf-8"))


def test_services_are_running_and_connected():
    client = redis.Redis(host="127.0.0.1", port=6379, socket_connect_timeout=2, socket_timeout=2)
    assert client.ping() is True, "Redis is not running on port 6379."
    client.flushdb()

    last_error = None
    backend_result = node_result = None
    value = 1e-46
    for _ in range(12):
        try:
            backend_result = post_json("http://127.0.0.1:8002/infer", {"val": value})
            node_result = post_json("http://127.0.0.1:8001/infer", {"val": value})
            break
        except Exception as exc:
            last_error = exc
            time.sleep(0.25)
    else:
        pytest.fail(f"The inference and preprocessing services are not operational: {last_error}")

    assert "result" in backend_result and "result" in node_result
    assert math.isclose(float(backend_result["result"]), value, rel_tol=0.0, abs_tol=1e-60), \
        "Backend inference lost float64 precision."
    assert math.isclose(float(node_result["result"]), value, rel_tol=0.0, abs_tol=1e-60), \
        "Node preprocessing service did not preserve the backend result."
    assert client.dbsize() > 0, "Inference requests did not populate Redis; backend cache connectivity is broken."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
