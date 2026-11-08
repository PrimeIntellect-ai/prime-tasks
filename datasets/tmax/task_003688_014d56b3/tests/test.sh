#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import grp
import json
import os
import pwd
import random
import secrets
import string
import subprocess
import tempfile
import uuid

import pytest

SCRIPT_PATH = "/home/user/filter_vm_requests.py"
CLEAN_CORPUS = "/eval/clean_corpus"
EVIL_CORPUS = "/eval/evil_corpus"
TOKEN_CHECKER = "/app/check_token"


def run_submission(path):
    return subprocess.run([SCRIPT_PATH, path], capture_output=True, timeout=5)


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."
    with open(SCRIPT_PATH, "rb") as f:
        first_line = f.readline().decode("utf-8", "replace").strip()
    assert first_line.startswith("#!") and "python3" in first_line, \
        "Script must begin with a Python 3 shebang."


def test_clean_corpus():
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS, "*.json"))
    assert len(clean_files) > 0, f"No clean corpus files found in {CLEAN_CORPUS}."

    failed_files = []
    for f in sorted(clean_files):
        result = subprocess.run([SCRIPT_PATH, f], capture_output=True)
        if result.returncode != 0:
            failed_files.append(os.path.basename(f))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean files rejected: {', '.join(failed_files)}")


def test_evil_corpus():
    evil_files = glob.glob(os.path.join(EVIL_CORPUS, "*.json"))
    assert len(evil_files) > 0, f"No evil corpus files found in {EVIL_CORPUS}."

    bypassed_files = []
    for f in sorted(evil_files):
        result = subprocess.run([SCRIPT_PATH, f], capture_output=True)
        if result.returncode == 0:
            bypassed_files.append(os.path.basename(f))

    if bypassed_files:
        pytest.fail(f"{len(bypassed_files)} of {len(evil_files)} evil files bypassed: {', '.join(bypassed_files)}")


def is_unprivileged_existing_user(username):
    if not isinstance(username, str):
        return False
    try:
        entry = pwd.getpwnam(username)
    except KeyError:
        return False
    for group_name in ("sudo", "wheel"):
        try:
            group = grp.getgrnam(group_name)
        except KeyError:
            continue
        if entry.pw_gid == group.gr_gid or username in group.gr_mem:
            return False
    return True


def oracle(payload):
    if not isinstance(payload, dict):
        return False
    if not is_unprivileged_existing_user(payload.get("username")):
        return False
    display = payload.get("vnc_display")
    if type(display) is not int or not 1 <= display <= 99:
        return False
    env = payload.get("env")
    if not isinstance(env, dict):
        return False
    if any("PRELOAD" in key or "BASH_ENV" in key for key in env):
        return False
    token = payload.get("vm_token")
    if not isinstance(token, str):
        return False
    return subprocess.run([TOKEN_CHECKER, token], capture_output=True, timeout=5).returncode == 0


def token_pools():
    valid = []
    invalid = []
    alphabet = string.ascii_letters + string.digits
    while len(valid) < 8 or len(invalid) < 8:
        token = "".join(secrets.choice(alphabet) for _ in range(secrets.choice(range(5, 15))))
        accepted = subprocess.run([TOKEN_CHECKER, token], capture_output=True, timeout=5).returncode == 0
        pool = valid if accepted else invalid
        if token not in pool:
            pool.append(token)
    return valid, invalid


def test_generated_requests_at_opaque_paths():
    valid_tokens, invalid_tokens = token_pools()
    clean_users = [entry.pw_name for entry in pwd.getpwall()
                   if is_unprivileged_existing_user(entry.pw_name)]
    assert clean_users, "No eligible unprivileged local user is available."
    clean_user = secrets.choice(clean_users)

    privileged_users = []
    for entry in pwd.getpwall():
        if not is_unprivileged_existing_user(entry.pw_name):
            try:
                pwd.getpwnam(entry.pw_name)
                privileged_users.append(entry.pw_name)
            except KeyError:
                pass
    assert privileged_users, "No sudo/wheel user is available for testing."

    base = {
        "username": clean_user,
        "vnc_display": secrets.choice(range(1, 100)),
        "env": {"QEMU_AUDIO_DRV": "none", "RANDOM_SETTING": secrets.token_hex(4)},
        "vm_token": secrets.choice(valid_tokens),
    }

    cases = []

    def add(payload):
        cases.append((payload, oracle(payload)))

    add(dict(base))
    for display in (1, 2, 98, 99):
        item = dict(base)
        item["vnc_display"] = display
        add(item)
    for display in (0, 100, -1, 1.0, "12", True, None):
        item = dict(base)
        item["vnc_display"] = display
        add(item)
    item = dict(base)
    del item["vnc_display"]
    add(item)

    for username in (secrets.choice(privileged_users),
                     "absent_" + secrets.token_hex(10), 123, None):
        item = dict(base)
        item["username"] = username
        add(item)
    item = dict(base)
    del item["username"]
    add(item)

    for env in ({"LD_PRELOAD": "/tmp/x"},
                {"MY_PRELOAD_OPTION": "1"},
                {"BASH_ENV": "/tmp/x"},
                {"SAFE_BASH_ENV_SETTING": "1"},
                [], "SAFE=1", None):
        item = dict(base)
        item["env"] = env
        add(item)
    item = dict(base)
    del item["env"]
    add(item)

    for token in valid_tokens[:4] + invalid_tokens[:4] + ["", "x", 123, None]:
        item = dict(base)
        item["vm_token"] = token
        add(item)
    item = dict(base)
    del item["vm_token"]
    add(item)

    rng = random.SystemRandom()
    username_options = [clean_user, secrets.choice(privileged_users),
                        "missing_" + secrets.token_hex(8), None]
    display_options = [1, 99, rng.randrange(2, 99), 0, 100, -5, "50", True, None]
    env_options = [{}, {"SAFE": "value"}, {"X_PRELOAD_Y": "1"},
                   {"X_BASH_ENV_Y": "1"}, [], None]
    token_options = valid_tokens + invalid_tokens + ["a", "", None, 7]
    for _ in range(100):
        payload = {
            "username": rng.choice(username_options),
            "vnc_display": rng.choice(display_options),
            "env": rng.choice(env_options),
            "vm_token": rng.choice(token_options),
            "extra_" + secrets.token_hex(3): secrets.token_hex(3),
        }
        if rng.randrange(8) == 0:
            del payload[rng.choice(["username", "vnc_display", "env", "vm_token"])]
        add(payload)

    add([])
    add(None)
    add("not an object")

    rng.shuffle(cases)
    directory = tempfile.mkdtemp(prefix="request_eval_" + secrets.token_hex(6) + "_")
    failures = []
    for payload, expected_clean in cases:
        path = os.path.join(directory, uuid.uuid4().hex + ".json")
        with open(path, "w", encoding="utf-8") as f:
            json.dump(payload, f)
        result = run_submission(path)
        actual_clean = result.returncode == 0
        if actual_clean != expected_clean:
            failures.append((path, expected_clean, result.returncode, payload))

    malformed_path = os.path.join(directory, uuid.uuid4().hex + ".json")
    with open(malformed_path, "w", encoding="utf-8") as f:
        f.write('{"username":')
    malformed_result = run_submission(malformed_path)
    if malformed_result.returncode == 0:
        failures.append((malformed_path, False, malformed_result.returncode, "malformed JSON"))

    assert not failures, "Generated request misclassifications: " + repr(failures[:10])
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
