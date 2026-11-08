#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import secrets
import shutil
import subprocess
import tempfile


def run_validator(validator, path):
    return subprocess.run([validator, path], capture_output=True, timeout=10).returncode


def telemetry_is_valid(path):
    try:
        with open(path, "r", encoding="utf-8") as fp:
            data = json.load(fp)
        if not isinstance(data, dict):
            return False
        if "device_id" not in data or "temperature" not in data:
            return False
        device_id = data["device_id"]
        if not isinstance(device_id, str) or re.fullmatch(r"[A-Za-z0-9-]+", device_id) is None:
            return False
        temp = data["temperature"]
        if isinstance(temp, bool) or not isinstance(temp, (int, float)):
            return False
        return -50 <= temp <= 150
    except Exception:
        return False


def test_adversarial_corpus_and_generated_cases():
    validator = "/home/user/verify_telemetry.sh"
    assert os.path.isfile(validator), f"{validator} does not exist"
    assert os.access(validator, os.X_OK), f"{validator} is not executable"

    clean_dir = "/app/corpus/clean/"
    evil_dir = "/app/corpus/evil/"
    clean_files = [f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    clean_failed = []
    for f in clean_files:
        path = os.path.join(clean_dir, f)
        res = subprocess.run(["bash", validator, path], capture_output=True, timeout=10)
        if res.returncode != 0:
            clean_failed.append(f)

    evil_bypassed = []
    for f in evil_files:
        path = os.path.join(evil_dir, f)
        res = subprocess.run(["bash", validator, path], capture_output=True, timeout=10)
        if res.returncode == 0:
            evil_bypassed.append(f)

    errors = []
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean rejected: {', '.join(clean_failed)}")
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    assert not errors, "Adversarial corpus failed:\n" + "\n".join(errors)

    token = secrets.token_hex(8)
    good_id = f"Node-{token}"
    low = random.randint(-49, 20)
    high = random.randint(21, 149)
    cases = [
        ({"device_id": good_id, "temperature": -50}, True),
        ({"device_id": good_id + "-Z9", "temperature": 150}, True),
        ({"device_id": good_id, "temperature": low + 0.375}, True),
        ({"device_id": good_id, "temperature": high}, True),
        ({"device_id": good_id, "temperature": -50.001}, False),
        ({"device_id": good_id, "temperature": 150.001}, False),
        ({"device_id": good_id, "temperature": str(low)}, False),
        ({"device_id": good_id, "temperature": True}, False),
        ({"device_id": good_id, "temperature": None}, False),
        ({"device_id": good_id + "_bad", "temperature": low}, False),
        ({"device_id": good_id + ";touch-pwned", "temperature": low}, False),
        ({"device_id": good_id + "$(id)", "temperature": low}, False),
        ({"device_id": "", "temperature": low}, False),
        ({"device_id": 12345, "temperature": low}, False),
        ({"temperature": low}, False),
        ({"device_id": good_id}, False),
        ([{"device_id": good_id, "temperature": low}], False),
    ]

    with tempfile.TemporaryDirectory(prefix="telemetry-generated-") as td:
        random.shuffle(cases)
        for payload, expected in cases:
            path = os.path.join(td, secrets.token_hex(12) + ".json")
            with open(path, "w", encoding="utf-8") as fp:
                json.dump(payload, fp)
            accepted = run_validator(validator, path) == 0
            assert accepted == expected, f"Validator returned the wrong result for generated payload {payload!r}"

        malformed = ["{", '{"device_id":"abc","temperature":1', "not json", ""]
        for content in malformed:
            path = os.path.join(td, secrets.token_hex(12) + ".json")
            with open(path, "w", encoding="utf-8") as fp:
                fp.write(content)
            assert run_validator(validator, path) != 0, f"Malformed JSON was accepted: {content!r}"

    no_arg = subprocess.run([validator], capture_output=True, timeout=10)
    assert no_arg.returncode != 0, "Validator accepted an invocation without a JSON path"


def test_deployment_script_is_executed_and_produces_state():
    deploy_script = "/home/user/deploy.sh"
    validator = "/home/user/verify_telemetry.sh"
    assert os.path.isfile(deploy_script), f"{deploy_script} does not exist"
    assert os.access(deploy_script, os.X_OK), f"{deploy_script} is not executable"

    deploy_id = "8675309"
    deploy_dir = f"/home/user/deployments/{deploy_id}"
    symlink = "/home/user/current_telemetry"
    incoming_dir = "/app/incoming"

    suffix = secrets.token_hex(8)
    generated = {
        f"valid-{suffix}.json": {"device_id": f"Factory-{suffix}", "temperature": random.randint(-40, 140)},
        f"valid-boundary-{suffix}.json": {"device_id": f"Boundary-{suffix}", "temperature": 150},
        f"invalid-id-{suffix}.json": {"device_id": f"bad_{suffix}", "temperature": 25},
        f"invalid-temp-{suffix}.json": {"device_id": f"Hot-{suffix}", "temperature": 151 + random.random()},
        f"invalid-type-{suffix}.json": {"device_id": f"Type-{suffix}", "temperature": "25"},
    }
    for name, payload in generated.items():
        with open(os.path.join(incoming_dir, name), "w", encoding="utf-8") as fp:
            json.dump(payload, fp)
    malformed_name = f"malformed-{suffix}.json"
    with open(os.path.join(incoming_dir, malformed_name), "w", encoding="utf-8") as fp:
        fp.write('{"device_id":"broken","temperature":')

    if os.path.lexists(symlink):
        if os.path.isdir(symlink) and not os.path.islink(symlink):
            shutil.rmtree(symlink)
        else:
            os.unlink(symlink)
    if os.path.lexists(deploy_dir):
        if os.path.isdir(deploy_dir) and not os.path.islink(deploy_dir):
            shutil.rmtree(deploy_dir)
        else:
            os.unlink(deploy_dir)

    marker = f"/tmp/validator-calls-{suffix}"
    backup = f"/tmp/agent-validator-{suffix}.sh"
    os.replace(validator, backup)
    wrapper = f'''#!/bin/bash
printf '%s\\n' "$1" >> {marker!r}
exec bash {backup!r} "$@"
'''
    with open(validator, "w", encoding="utf-8") as fp:
        fp.write(wrapper)
    os.chmod(validator, 0o755)

    try:
        result = subprocess.run([deploy_script], capture_output=True, text=True, timeout=30)
    finally:
        if os.path.lexists(validator):
            os.unlink(validator)
        os.replace(backup, validator)

    assert result.returncode == 0, f"deploy.sh failed when executed:\nstdout: {result.stdout}\nstderr: {result.stderr}"

    json_inputs = {
        os.path.abspath(os.path.join(incoming_dir, f))
        for f in os.listdir(incoming_dir)
        if f.endswith(".json") and os.path.isfile(os.path.join(incoming_dir, f))
    }
    assert os.path.isfile(marker), "deploy.sh did not invoke /home/user/verify_telemetry.sh"
    called = set()
    with open(marker, "r", encoding="utf-8") as fp:
        for raw in fp:
            value = raw.rstrip("\n")
            if not value:
                continue
            if os.path.isabs(value):
                called.add(os.path.abspath(value))
            else:
                called.add(os.path.abspath(os.path.join(incoming_dir, value)))
    missing_calls = json_inputs - called
    assert not missing_calls, f"deploy.sh did not validate every incoming JSON file: {missing_calls}"

    assert os.path.isdir(deploy_dir), f"Deployment directory {deploy_dir} does not exist. Did the deploy script run properly with the decoded ID?"
    assert os.path.islink(symlink), f"{symlink} is not a symlink"
    target = os.readlink(symlink)
    abs_target = os.path.normpath(os.path.join(os.path.dirname(symlink), target))
    assert abs_target == deploy_dir, f"Symlink points to {abs_target}, expected {deploy_dir}"

    expected_files = []
    for f in os.listdir(incoming_dir):
        path = os.path.join(incoming_dir, f)
        if not os.path.isfile(path) or not f.endswith('.json'):
            continue
        if telemetry_is_valid(path):
            expected_files.append(f)

    deployed_files = [f for f in os.listdir(deploy_dir) if os.path.isfile(os.path.join(deploy_dir, f))]
    missing = set(expected_files) - set(deployed_files)
    extra = set(deployed_files) - set(expected_files)
    assert not missing, f"Missing valid files in deployment directory: {missing}"
    assert not extra, f"Extra (invalid) files copied to deployment directory: {extra}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
