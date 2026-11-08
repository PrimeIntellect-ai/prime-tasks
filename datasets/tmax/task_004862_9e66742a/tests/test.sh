#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import re
import shutil
import stat
import subprocess
import tempfile
import uuid

PROJECT = "/home/user/release_manager"
EXPECTED_INPUT = [
    "eyJzZXJ2aWNlIjogImF1dGgiLCAiY3B1IjogMiwgIm1lbSI6IDQsICJ0aWVyIjogImNyaXRpY2FsIn0=",
    "eyJzZXJ2aWNlIjogInBheW1lbnQiLCAiY3B1IjogMiwgIm1lbSI6IDQsICJ0aWVyIjogImNyaXRpY2FsIn0=",
    "eyJzZXJ2aWNlIjogImxvZ2dpbmciLCAiY3B1IjogMiwgIm1lbSI6IDQsICJ0aWVyIjogInN0YW5kYXJkIn0=",
    "eyJzZXJ2aWNlIjogImJpbGxpbmciLCAiY3B1IjogMiwgIm1lbSI6IDQsICJ0aWVyIjogImNyaXRpY2FsIn0=",
    "eyJzZXJ2aWNlIjogImNhY2hlIiwgImNwdSI6IDgsICJtZW0iOiAxNiwgInRpZXIiOiAic3RhbmRhcmQifQ==",
    "eyJzZXJ2aWNlIjogInNlYXJjaCIsICJjcHUiOiA0LCAibWVtIjogOCwgInRpZXIiOiAic3RhbmRhcmQifQ==",
]


def run(cmd, **kwargs):
    return subprocess.run(cmd, cwd=PROJECT, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, timeout=30, **kwargs)


def test_original_artifact_assertions():
    plan_path = os.path.join(PROJECT, "deploy_plan.txt")
    assert os.path.isfile(plan_path), f"{plan_path} does not exist."
    with open(plan_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    expected_lines = ["auth", "payment", "logging", "cache"]
    assert lines == expected_lines, f"deploy_plan.txt content is incorrect. Expected {expected_lines}, got {lines}."

    input_path = os.path.join(PROJECT, "input.b64")
    assert os.path.isfile(input_path), f"{input_path} does not exist."
    with open(input_path, "r") as f:
        actual_input = [line.strip() for line in f if line.strip()]
    assert actual_input == EXPECTED_INPUT, "input.b64 does not contain the required Base64 manifests."

    validator_c = os.path.join(PROJECT, "validator.c")
    test_validator_c = os.path.join(PROJECT, "test_validator.c")
    assert os.path.isfile(validator_c), f"{validator_c} does not exist."
    assert os.path.isfile(test_validator_c), f"{test_validator_c} does not exist."

    cjson_c = os.path.join(PROJECT, "lib", "cJSON.c")
    cjson_h = os.path.join(PROJECT, "lib", "cJSON.h")
    assert os.path.isfile(cjson_c), f"{cjson_c} does not exist."
    assert os.path.isfile(cjson_h), f"{cjson_h} does not exist."
    assert os.path.getsize(cjson_c) > 1000 and os.path.getsize(cjson_h) > 1000, "cJSON files are empty or placeholders."

    log_path = os.path.join(PROJECT, "test_results.log")
    assert os.path.isfile(log_path), f"{log_path} does not exist."

    source = open(validator_c, "r", errors="replace").read()
    assert re.search(r"cJSON_Parse(?:WithOpts|WithLengthOpts|WithLength)?\s*\(", source), "validator.c does not call cJSON to parse JSON."
    assert re.search(r"base64", source, re.I) and re.search(r"decode", source, re.I), "validator.c does not contain a custom Base64 decoder."

    test_source = open(test_validator_c, "r", errors="replace").read()
    checks = re.findall(r"\b(?:assert|ASSERT\w*|CHECK\w*)\s*\(", test_source)
    assert len(checks) >= 2, "test_validator.c must contain at least two assertion/check cases."


def test_build_and_execute_unit_tests():
    log_path = os.path.join(PROJECT, "test_results.log")
    if os.path.exists(log_path):
        os.unlink(log_path)

    build_ran = False
    makefile = next((p for p in ("Makefile", "makefile", "GNUmakefile")
                     if os.path.isfile(os.path.join(PROJECT, p))), None)
    if makefile:
        result = run(["make", "-f", makefile])
        assert result.returncode == 0, "Project build failed:\n" + result.stdout
        build_ran = True
    else:
        scripts = []
        for name in sorted(os.listdir(PROJECT)):
            path = os.path.join(PROJECT, name)
            if os.path.isfile(path) and name.endswith(".sh"):
                scripts.append(path)
        assert scripts, "No Makefile or bash build script was provided."
        outputs = []
        for script in scripts:
            result = run(["bash", script])
            outputs.append(result.stdout)
            if result.returncode == 0:
                build_ran = True
                if os.path.isfile(log_path) and os.path.getsize(log_path) > 0:
                    break
        assert build_ran, "No provided build script completed successfully:\n" + "\n".join(outputs)

    # If the build did not itself recreate the test log, execute the test binary it built.
    if not (os.path.isfile(log_path) and os.path.getsize(log_path) > 0):
        candidates = []
        for root, dirs, files in os.walk(PROJECT):
            if root.count(os.sep) - PROJECT.count(os.sep) > 3:
                dirs[:] = []
                continue
            for name in files:
                path = os.path.join(root, name)
                if "test" in name.lower() and not name.endswith((".c", ".h", ".o", ".sh", ".log")):
                    try:
                        if os.stat(path).st_mode & stat.S_IXUSR:
                            candidates.append(path)
                    except OSError:
                        pass
        test_output = None
        for executable in candidates:
            result = run([executable])
            if result.returncode == 0:
                test_output = result.stdout or "unit tests completed successfully\n"
                break
        assert test_output is not None, "The unit-test executable could not be found or did not pass."
        with open(log_path, "w") as f:
            f.write(test_output)

    assert os.path.isfile(log_path) and os.path.getsize(log_path) > 0, "Unit tests did not produce test_results.log."


def expected_plan(manifests):
    cpu = memory = critical = 0
    accepted = []
    for item in manifests:
        next_critical = critical + (1 if item["tier"] == "critical" else 0)
        if cpu + item["cpu"] > 16 or memory + item["mem"] > 32 or next_critical > 2:
            continue
        cpu += item["cpu"]
        memory += item["mem"]
        critical = next_critical
        accepted.append(item["service"])
    return accepted


def encode_batch(manifests):
    encoded = []
    for index, item in enumerate(manifests):
        obj = dict(item)
        obj["metadata"] = {"sequence": index, "ignored": True}
        raw = json.dumps(obj, separators=(",", ":") if index % 2 else (", ", ": ")).encode()
        encoded.append(base64.b64encode(raw).decode())
    return "\n".join(encoded) + "\n"


def test_compiled_validator_on_unpredictable_batches():
    validator = os.path.join(PROJECT, "validator.c")
    cjson = os.path.join(PROJECT, "lib", "cJSON.c")
    binary = os.path.join(tempfile.mkdtemp(prefix="validator-check-"), "validator")
    result = run(["gcc", "-std=c11", "-O2", "-Ilib", validator, cjson, "-lm", "-o", binary])
    assert result.returncode == 0, "validator.c and cJSON.c do not compile:\n" + result.stdout

    token = uuid.uuid4().hex[:12]
    batches = [
        [
            {"service": f"alpha_{token}", "cpu": 3, "mem": 5, "tier": "critical"},
            {"service": f"beta_{token}", "cpu": 4, "mem": 7, "tier": "critical"},
            {"service": f"thirdcrit_{token}", "cpu": 1, "mem": 1, "tier": "critical"},
            {"service": f"standard_{token}", "cpu": 8, "mem": 19, "tier": "standard"},
            {"service": f"cpu_over_{token}", "cpu": 2, "mem": 1, "tier": "standard"},
        ],
        [
            {"service": f"oversized_{token}", "cpu": 17, "mem": 1, "tier": "standard"},
            {"service": f"after_reject_{token}", "cpu": 16, "mem": 32, "tier": "standard"},
            {"service": f"no_room_{token}", "cpu": 1, "mem": 1, "tier": "standard"},
        ],
        [
            {"service": f"m1_{token}", "cpu": 2, "mem": 20, "tier": "standard"},
            {"service": f"mem_reject_{token}", "cpu": 2, "mem": 13, "tier": "standard"},
            {"service": f"m2_{token}", "cpu": 6, "mem": 12, "tier": "critical"},
            {"service": f"m3_{token}", "cpu": 8, "mem": 1, "tier": "critical"},
        ],
    ]

    input_path = os.path.join(PROJECT, "input.b64")
    plan_path = os.path.join(PROJECT, "deploy_plan.txt")
    original_input = open(input_path, "rb").read()
    original_plan = open(plan_path, "rb").read() if os.path.exists(plan_path) else None
    try:
        for manifests in batches:
            with open(input_path, "w") as f:
                f.write(encode_batch(manifests))
            if os.path.exists(plan_path):
                os.unlink(plan_path)
            result = run([binary])
            assert result.returncode == 0, "Compiled validator failed:\n" + result.stdout
            assert os.path.isfile(plan_path), "Compiled validator did not generate deploy_plan.txt."
            with open(plan_path, "r") as f:
                actual = [line.strip() for line in f if line.strip()]
            expected = expected_plan(manifests)
            assert actual == expected, f"Validator produced {actual}; expected {expected}."
    finally:
        with open(input_path, "wb") as f:
            f.write(original_input)
        if original_plan is None:
            if os.path.exists(plan_path):
                os.unlink(plan_path)
        else:
            with open(plan_path, "wb") as f:
                f.write(original_plan)
        shutil.rmtree(os.path.dirname(binary), ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
