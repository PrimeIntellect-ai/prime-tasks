#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import re
import secrets
import ssl
import subprocess
import tempfile
import urllib.error
import urllib.request

import pytest

SCRIPT_PATH = "/home/user/finops_filter.py"
DEPLOY_SCRIPT = "/home/user/deploy.sh"
WWW_ROOT = "/home/user/www"
APPROVED = ("t4g", "m6g", "c6g")
MAX_COST = 1200


def run_filter(path):
    return subprocess.run(
        ["python3", SCRIPT_PATH, path], capture_output=True, timeout=5
    )


def expected_approval(config):
    return (
        all(
            any(instance["type"].startswith(family) for family in APPROVED)
            for instance in config["instances"]
        )
        and sum(
            instance["count"] * instance["monthly_cost_per_unit"]
            for instance in config["instances"]
        ) <= MAX_COST
    )


def test_finops_filter_adversarial_corpus():
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} does not exist"

    clean_dir = "/opt/verifier/clean"
    evil_dir = "/opt/verifier/evil"

    clean_files = glob.glob(os.path.join(clean_dir, "*.json"))
    evil_files = glob.glob(os.path.join(evil_dir, "*.json"))

    assert len(clean_files) > 0, "No clean corpus files found."
    assert len(evil_files) > 0, "No evil corpus files found."

    clean_failed = []
    for cf in clean_files:
        result = run_filter(cf)
        if result.returncode != 0:
            clean_failed.append(os.path.basename(cf))

    evil_bypassed = []
    for ef in evil_files:
        result = run_filter(ef)
        if result.returncode == 0:
            evil_bypassed.append(os.path.basename(ef))

    errors = []
    if clean_failed:
        errors.append(
            f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: "
            + ", ".join(clean_failed)
        )
    if evil_bypassed:
        errors.append(
            f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: "
            + ", ".join(evil_bypassed)
        )

    assert not errors, " | ".join(errors)


def test_finops_filter_generated_inputs():
    rng = random.SystemRandom()
    workdir = tempfile.mkdtemp(prefix="finops-inputs-")
    cases = []

    # Explicitly exercise the exact cost boundary.
    boundary_count = rng.choice([1, 2, 3, 4, 5, 6, 8, 10, 12])
    cases.append({
        "app_name": "svc-" + secrets.token_hex(6),
        "instances": [{
            "type": rng.choice(APPROVED) + "." + secrets.token_hex(3),
            "count": boundary_count,
            "monthly_cost_per_unit": MAX_COST // boundary_count,
        }],
    })

    for i in range(40):
        mode = i % 4
        app_name = "svc-" + secrets.token_hex(7)
        if mode == 0:
            first_cost = rng.randint(1, 700)
            second_cost = rng.randint(1, MAX_COST - first_cost)
            instances = [
                {
                    "type": rng.choice(APPROVED) + "." + secrets.token_hex(3),
                    "count": 1,
                    "monthly_cost_per_unit": first_cost,
                },
                {
                    "type": rng.choice(APPROVED) + "." + secrets.token_hex(3),
                    "count": 1,
                    "monthly_cost_per_unit": second_cost,
                },
            ]
        elif mode == 1:
            instances = [{
                "type": rng.choice(("r5", "x2", "z9")) + "." + secrets.token_hex(3),
                "count": rng.randint(1, 4),
                "monthly_cost_per_unit": rng.randint(1, 50),
            }]
        elif mode == 2:
            count = rng.randint(1, 8)
            unit_cost = MAX_COST // count + rng.randint(1, 200)
            instances = [{
                "type": rng.choice(APPROVED) + "." + secrets.token_hex(3),
                "count": count,
                "monthly_cost_per_unit": unit_cost,
            }]
        else:
            instances = [
                {
                    "type": rng.choice(APPROVED) + "." + secrets.token_hex(3),
                    "count": 1,
                    "monthly_cost_per_unit": rng.randint(1, 100),
                },
                {
                    "type": rng.choice(("a1", "p4", "r7")) + "." + secrets.token_hex(3),
                    "count": 1,
                    "monthly_cost_per_unit": rng.randint(1, 100),
                },
            ]
        cases.append({"app_name": app_name, "instances": instances})

    rng.shuffle(cases)
    saw_approved = False
    saw_rejected = False
    for config in cases:
        expected = expected_approval(config)
        saw_approved |= expected
        saw_rejected |= not expected
        path = os.path.join(workdir, secrets.token_hex(12) + ".json")
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(config, handle, separators=(",", ":"))
        result = run_filter(path)
        assert (result.returncode == 0) == expected, (
            f"Filter returned {result.returncode} for generated configuration {config}; "
            f"expected {'approval' if expected else 'rejection'}. "
            f"stderr={result.stderr.decode(errors='replace')}"
        )

    assert saw_approved and saw_rejected


def test_nginx_running_tls():
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    try:
        req = urllib.request.Request("https://localhost:8443/")
        with urllib.request.urlopen(req, context=ctx, timeout=2) as response:
            assert response.status in [200, 403, 404], (
                f"Unexpected status code: {response.status}"
            )
    except urllib.error.URLError as exc:
        pytest.fail(f"Failed to connect to nginx on port 8443 with TLS: {exc}")

    # Verify that nginx's active configuration names the required TLS listener
    # and document root, rather than accepting an unrelated TLS service.
    config = subprocess.run(
        ["nginx", "-T"], capture_output=True, text=True, timeout=5
    )
    assert config.returncode == 0, config.stderr
    rendered = config.stdout + "\n" + config.stderr
    assert re.search(r"(?m)^\s*listen\s+8443(?:\s+[^;]*)?\bssl\b[^;]*;", rendered), (
        "Active nginx configuration does not contain an SSL listener on 8443"
    )
    assert re.search(r"(?m)^\s*root\s+/home/user/www\s*;", rendered), (
        "Active nginx configuration does not use /home/user/www as a document root"
    )

    marker_name = "dashboard-check-" + secrets.token_hex(10) + ".txt"
    marker_value = "marker-" + secrets.token_hex(24)
    marker_path = os.path.join(WWW_ROOT, marker_name)
    os.makedirs(WWW_ROOT, exist_ok=True)
    with open(marker_path, "w", encoding="utf-8") as handle:
        handle.write(marker_value)

    try:
        with urllib.request.urlopen(
            f"https://localhost:8443/{marker_name}", context=ctx, timeout=2
        ) as response:
            body = response.read().decode("utf-8")
            assert response.status == 200
            assert body == marker_value, "nginx did not serve content from /home/user/www"
    finally:
        os.unlink(marker_path)

    pem = ssl.get_server_certificate(("localhost", 8443))
    cert_info = subprocess.run(
        ["openssl", "x509", "-noout", "-subject", "-issuer"],
        input=pem,
        text=True,
        capture_output=True,
        timeout=5,
    )
    assert cert_info.returncode == 0, cert_info.stderr
    fields = {}
    for line in cert_info.stdout.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            fields[key.strip()] = value.strip()
    assert fields.get("subject") and fields.get("issuer")
    assert fields["subject"] == fields["issuer"], "TLS certificate is not self-signed"


def resolve_live_target(link_path):
    target = os.readlink(link_path)
    if not os.path.isabs(target):
        target = os.path.join(os.path.dirname(link_path), target)
    return os.path.realpath(target)


def assert_successful_deployment(app_name, source_path):
    result = subprocess.run(
        ["bash", DEPLOY_SCRIPT, source_path], capture_output=True, timeout=10
    )
    assert result.returncode == 0, (
        f"Deploy script failed on valid config: {result.stderr.decode(errors='replace')}"
    )

    symlink_path = os.path.join(WWW_ROOT, app_name + "-live")
    assert os.path.islink(symlink_path), f"Symlink {symlink_path} was not created"
    target_dir = resolve_live_target(symlink_path)
    assert os.path.commonpath([os.path.realpath(WWW_ROOT), target_dir]) == os.path.realpath(WWW_ROOT)
    assert os.path.basename(target_dir).startswith(app_name + "-")
    assert os.path.isdir(target_dir), f"Symlink target {target_dir} is not a directory"

    copied_config = os.path.join(target_dir, "config.json")
    assert os.path.isfile(copied_config), f"config.json not found in {target_dir}"
    with open(source_path, "rb") as source, open(copied_config, "rb") as copied:
        assert copied.read() == source.read(), "Deployed config.json is not a copy of the input"


def test_deploy_script():
    assert os.path.isfile(DEPLOY_SCRIPT), f"{DEPLOY_SCRIPT} does not exist"
    assert os.access(DEPLOY_SCRIPT, os.X_OK), f"{DEPLOY_SCRIPT} is not executable"

    # Preserve the original accepted deployment check.
    test_app_name = "test-api-service"
    valid_config = {
        "app_name": test_app_name,
        "instances": [
            {"type": "t4g.micro", "count": 1, "monthly_cost_per_unit": 10}
        ],
    }
    test_conf_path = "/tmp/test_valid_config.json"
    with open(test_conf_path, "w") as handle:
        json.dump(valid_config, handle)

    assert_successful_deployment(test_app_name, test_conf_path)

    invalid_config = {
        "app_name": "test-evil-service",
        "instances": [
            {"type": "t4g.micro", "count": 1000, "monthly_cost_per_unit": 10}
        ],
    }
    test_evil_path = "/tmp/test_evil_config.json"
    with open(test_evil_path, "w") as handle:
        json.dump(invalid_config, handle)

    result_evil = subprocess.run(
        ["bash", DEPLOY_SCRIPT, test_evil_path], capture_output=True, timeout=10
    )
    assert result_evil.returncode != 0, "Deploy script should fail on invalid config"
    evil_symlink = "/home/user/www/test-evil-service-live"
    assert not os.path.exists(evil_symlink), (
        f"Symlink {evil_symlink} should not exist for rejected config"
    )

    # Exercise opaque, newly generated app names and contents so deployment
    # behavior cannot be selected by the fixed names or files above.
    rng = random.SystemRandom()
    workdir = tempfile.mkdtemp(prefix="deployment-inputs-")
    for _ in range(3):
        app_name = "app-" + secrets.token_hex(8)
        count = rng.randint(1, 6)
        config = {
            "app_name": app_name,
            "instances": [{
                "type": rng.choice(APPROVED) + "." + secrets.token_hex(3),
                "count": count,
                "monthly_cost_per_unit": rng.randint(1, MAX_COST // count),
            }],
        }
        path = os.path.join(workdir, secrets.token_hex(12) + ".json")
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(config, handle, indent=rng.choice([None, 2, 4]))

        assert_successful_deployment(app_name, path)
        # Repeating the same deployment must remain safe and successful.
        assert_successful_deployment(app_name, path)

    for mode in ("family", "cost", "mixed"):
        app_name = "app-" + secrets.token_hex(8)
        if mode == "family":
            instances = [{
                "type": rng.choice(("r5", "x1", "p4")) + "." + secrets.token_hex(3),
                "count": 1,
                "monthly_cost_per_unit": rng.randint(1, 100),
            }]
        elif mode == "cost":
            instances = [{
                "type": rng.choice(APPROVED) + "." + secrets.token_hex(3),
                "count": 1,
                "monthly_cost_per_unit": MAX_COST + rng.randint(1, 500),
            }]
        else:
            instances = [
                {"type": "t4g." + secrets.token_hex(3), "count": 1, "monthly_cost_per_unit": 5},
                {"type": "r7." + secrets.token_hex(3), "count": 1, "monthly_cost_per_unit": 5},
            ]

        path = os.path.join(workdir, secrets.token_hex(12) + ".json")
        with open(path, "w", encoding="utf-8") as handle:
            json.dump({"app_name": app_name, "instances": instances}, handle)

        before = set(glob.glob(os.path.join(WWW_ROOT, app_name + "-*")))
        result = subprocess.run(
            ["bash", DEPLOY_SCRIPT, path], capture_output=True, timeout=10
        )
        assert result.returncode != 0, "Deploy script accepted a generated invalid config"
        live = os.path.join(WWW_ROOT, app_name + "-live")
        assert not os.path.lexists(live), "Rejected deployment created a live symlink"
        after = set(glob.glob(os.path.join(WWW_ROOT, app_name + "-*")))
        assert after == before, "Rejected deployment created deployment artifacts"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
