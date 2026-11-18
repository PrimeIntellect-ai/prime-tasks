#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import os
import re
import subprocess
import tempfile

import pytest

REPORT_PATH = "/home/user/rotation_report.json"
GENERATOR_PATH = "/home/user/generate_key.py"
OLD_KEY_PATH = "/home/user/old_key.txt"
BUNDLE_PATH = "/home/user/bundle.pem"


def test_report_exists():
    assert os.path.isfile(REPORT_PATH), f"Expected report file {REPORT_PATH} is missing."


def test_report_is_valid_json():
    with open(REPORT_PATH, "r") as f:
        try:
            json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {REPORT_PATH} does not contain valid JSON.")


def _expected_seed():
    with open(OLD_KEY_PATH, "r") as f:
        key = int(f.read().strip())
    assert key == 153028214, "The supplied old key was unexpectedly modified."

    a = 1103515245
    c = 12345
    m = 2147483647
    return ((key - c) * pow(a, -1, m)) % m, key


def _load_generator():
    spec = importlib.util.spec_from_file_location("generate_key", GENERATOR_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _validated_leaf_cn():
    with open(BUNDLE_PATH, "r") as f:
        bundle = f.read()

    certs = re.findall(
        r"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----",
        bundle,
        flags=re.DOTALL,
    )
    assert len(certs) == 3, f"Expected exactly three certificates in the bundle, found {len(certs)}."

    with tempfile.TemporaryDirectory() as tmpdir:
        paths = []
        for index, cert in enumerate(certs):
            path = os.path.join(tmpdir, f"cert-{index}.pem")
            with open(path, "w") as f:
                f.write(cert + "\n")
            paths.append(path)

        leaf, intermediate, root = paths
        subprocess.run(
            ["openssl", "verify", "-CAfile", root, root],
            check=True,
            capture_output=True,
            text=True,
        )
        subprocess.run(
            ["openssl", "verify", "-CAfile", root, "-untrusted", intermediate, leaf],
            check=True,
            capture_output=True,
            text=True,
        )
        subject = subprocess.run(
            ["openssl", "x509", "-in", leaf, "-noout", "-subject", "-nameopt", "RFC2253"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()

    match = re.search(r"(?:^|,)CN=([^,]+)", subject.removeprefix("subject="))
    assert match, f"Leaf certificate subject has no CN: {subject}"
    return match.group(1)


def test_report_contents():
    with open(REPORT_PATH, "r") as f:
        data = json.load(f)

    assert isinstance(data, dict), f"Expected JSON root to be a dictionary, got {type(data).__name__}."

    expected_keys = {"cwe", "seed", "cert_cn"}
    missing_keys = expected_keys - set(data.keys())
    assert not missing_keys, f"Report is missing required keys: {', '.join(missing_keys)}"

    cwe = data.get("cwe")
    assert cwe == "CWE-338", f"Expected 'cwe' to be 'CWE-338', but got '{cwe}'."

    expected_seed, old_key = _expected_seed()
    seed = data.get("seed")
    assert isinstance(seed, int) and not isinstance(seed, bool), "Expected 'seed' to be an integer."
    assert seed == expected_seed, f"Expected 'seed' to be {expected_seed}, but got {seed}."

    generator = _load_generator()
    assert generator.generate_key(seed) == old_key, "Reported seed does not generate the supplied old key."

    expected_cn = _validated_leaf_cn()
    cert_cn = data.get("cert_cn")
    assert cert_cn == "internal-service.local", f"Expected 'cert_cn' to be 'internal-service.local', but got '{cert_cn}'."
    assert cert_cn == expected_cn, f"Reported CN '{cert_cn}' does not match validated leaf CN '{expected_cn}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
