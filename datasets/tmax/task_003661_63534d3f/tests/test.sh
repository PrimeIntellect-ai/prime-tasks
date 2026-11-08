#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import stat
import subprocess
import tempfile
import uuid
import pytest

SCRIPT_PATH = "/home/user/validate_vm"
CLEAN_CORPUS_PATH = "/app/configs/clean"
EVIL_CORPUS_PATH = "/app/configs/evil"

TOPOLOGY = {
    "auth": (5901, "/home/user/vms/auth_data"),
    "backend": (5902, "/home/user/vms/backend_data"),
    "cache": (5903, "/home/user/vms/cache_data"),
}


def run_validator(path):
    try:
        return subprocess.run(
            [SCRIPT_PATH, path], capture_output=True, timeout=5
        ).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"Validator timed out for {path}")


def expected_valid(config):
    if not isinstance(config, dict):
        return False
    service = config.get("service")
    if service not in TOPOLOGY:
        return False
    port, base = TOPOLOGY[service]
    if config.get("vnc_port") != port:
        return False
    mount = config.get("host_mount")
    if not isinstance(mount, str) or not os.path.isabs(mount):
        return False
    real_base = os.path.realpath(base)
    real_mount = os.path.realpath(mount)
    try:
        return os.path.commonpath([real_base, real_mount]) == real_base
    except (TypeError, ValueError):
        return False


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Validation script not found at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"Validation script {SCRIPT_PATH} is not a file"
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Validation script {SCRIPT_PATH} is not executable"


def test_adversarial_corpus():
    if not os.path.exists(SCRIPT_PATH) or not os.access(SCRIPT_PATH, os.X_OK):
        pytest.fail(f"Script {SCRIPT_PATH} is missing or not executable.")

    clean_files = [os.path.join(CLEAN_CORPUS_PATH, f) for f in os.listdir(CLEAN_CORPUS_PATH) if f.endswith('.json')]
    evil_files = [os.path.join(EVIL_CORPUS_PATH, f) for f in os.listdir(EVIL_CORPUS_PATH) if f.endswith('.json')]

    clean_failed = []
    for cf in clean_files:
        if run_validator(cf) != 0:
            clean_failed.append(os.path.basename(cf))

    evil_bypassed = []
    for ef in evil_files:
        if run_validator(ef) == 0:
            evil_bypassed.append(os.path.basename(ef))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failed)}")
    if errors:
        pytest.fail(" | ".join(errors))


def test_generated_hidden_configurations():
    token = uuid.uuid4().hex
    outside = os.path.join("/home/user", f"validation_outside_{token}")
    prefix_sibling = os.path.join("/home/user/vms", f"auth_data_not_auth_{token}")
    os.makedirs(outside, exist_ok=True)
    os.makedirs(prefix_sibling, exist_ok=True)

    cases = []
    for service, (port, base) in TOPOLOGY.items():
        inner = os.path.join(base, f"hidden_{token}_{service}", "data")
        os.makedirs(inner, exist_ok=True)

        link_target = os.path.join(base, f"hidden_target_{token}_{service}")
        os.makedirs(link_target, exist_ok=True)
        internal_link = os.path.join(base, f"hidden_link_{token}_{service}")
        if os.path.lexists(internal_link):
            os.unlink(internal_link)
        os.symlink(link_target, internal_link)

        external_link = os.path.join(base, f"hidden_escape_{token}_{service}")
        if os.path.lexists(external_link):
            os.unlink(external_link)
        os.symlink(outside, external_link)

        cases.extend([
            {"service": service, "vnc_port": port, "host_mount": base},
            {"service": service, "vnc_port": port, "host_mount": inner},
            {"service": service, "vnc_port": port, "host_mount": os.path.join(inner, "..", "data")},
            {"service": service, "vnc_port": port, "host_mount": internal_link},
            {"service": service, "vnc_port": port + 100, "host_mount": inner},
            {"service": service, "vnc_port": port, "host_mount": external_link},
            {"service": service, "vnc_port": port, "host_mount": os.path.join(base, "..", os.path.basename(outside))},
        ])

    cases.extend([
        {"service": "auth", "vnc_port": 5901, "host_mount": prefix_sibling},
        {"service": "auth", "vnc_port": 5901, "host_mount": "/home/user/vms/backend_data"},
        {"service": "backend", "vnc_port": 5902, "host_mount": "/home/user/vms/cache_data"},
        {"service": "unknown", "vnc_port": 5901, "host_mount": "/home/user/vms/auth_data"},
        {"service": "auth", "vnc_port": "5901", "host_mount": "/home/user/vms/auth_data"},
        {"service": "auth", "vnc_port": 5901, "host_mount": "relative/path"},
        {"service": "auth", "vnc_port": 5901},
        {"vnc_port": 5901, "host_mount": "/home/user/vms/auth_data"},
    ])

    random.SystemRandom().shuffle(cases)
    failures = []
    with tempfile.TemporaryDirectory(prefix=f"vm_validation_{token}_") as config_dir:
        generated = []
        for config in cases:
            path = os.path.join(config_dir, f"{uuid.uuid4().hex}.json")
            with open(path, "w", encoding="utf-8") as fh:
                json.dump(config, fh)
            generated.append((path, expected_valid(config)))

        malformed = os.path.join(config_dir, f"{uuid.uuid4().hex}.json")
        with open(malformed, "w", encoding="utf-8") as fh:
            fh.write('{"service": "auth", "vnc_port": 5901,')
        generated.append((malformed, False))

        scalar = os.path.join(config_dir, f"{uuid.uuid4().hex}.json")
        with open(scalar, "w", encoding="utf-8") as fh:
            json.dump(["auth", 5901, "/home/user/vms/auth_data"], fh)
        generated.append((scalar, False))

        random.SystemRandom().shuffle(generated)
        for path, should_accept in generated:
            accepted = run_validator(path) == 0
            if accepted != should_accept:
                failures.append((os.path.basename(path), should_accept, accepted))

    assert not failures, f"Generated configuration misclassifications: {failures}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
