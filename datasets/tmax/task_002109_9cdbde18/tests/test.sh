#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import shlex
import stat
import string
import subprocess
import tempfile
import time
import uuid

import pytest
import yaml


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def network_names(value):
    if isinstance(value, list):
        return set(value)
    if isinstance(value, dict):
        return set(value.keys())
    return set()


def test_docker_compose_network_fix():
    compose_path = "/home/user/capacity-stack/docker-compose.yml"
    assert os.path.isfile(compose_path), f"Missing {compose_path}"

    with open(compose_path, "r") as f:
        compose_data = yaml.safe_load(f)

    services = compose_data.get("services", {})
    assert "log_aggregator" in services, "log_aggregator service missing"
    assert "db" in services, "db service missing"

    log_aggregator_nets = network_names(services["log_aggregator"].get("networks", []))
    db_nets = network_names(services["db"].get("networks", []))

    # Preserve the original assertions.
    assert "capacity_net" in log_aggregator_nets, "log_aggregator is not on capacity_net"
    assert "capacity_net" in db_nets, "db is not on capacity_net"

    assert log_aggregator_nets == {"capacity_net"}, "log_aggregator must use only capacity_net"
    assert db_nets == {"capacity_net"}, "db must use only capacity_net"

    networks = compose_data.get("networks", {})
    assert "capacity_net" in networks, "capacity_net is not defined at the top level"
    net_definition = networks["capacity_net"] or {}
    assert isinstance(net_definition, dict), "capacity_net has an invalid definition"
    assert net_definition.get("driver", "bridge") == "bridge", "capacity_net must use the bridge driver"

    validated = run(["docker-compose", "-f", compose_path, "config"], timeout=30)
    assert validated.returncode == 0, f"Invalid Compose file:\n{validated.stdout}\n{validated.stderr}"

    project = "capacityverify_" + uuid.uuid4().hex[:10]
    base = ["docker-compose", "-p", project, "-f", compose_path]
    try:
        started = run(base + ["up", "-d"], timeout=120)
        assert started.returncode == 0, f"Compose stack failed to start:\n{started.stdout}\n{started.stderr}"

        ids = {}
        for service in ("log_aggregator", "db"):
            result = run(base + ["ps", "-q", service], timeout=20)
            assert result.returncode == 0 and result.stdout.strip(), f"{service} is not running"
            ids[service] = result.stdout.strip().splitlines()[0]

        attached = {}
        for service, container_id in ids.items():
            result = run(["docker", "inspect", "-f", "{{json .NetworkSettings.Networks}}", container_id], timeout=20)
            assert result.returncode == 0, result.stderr
            attached[service] = json.loads(result.stdout)

        common = set(attached["log_aggregator"]) & set(attached["db"])
        assert common, "The services do not share an actual Docker network"
        assert len(attached["log_aggregator"]) == 1 and len(attached["db"]) == 1, "Services must use a single network"

        network_id = attached["log_aggregator"][next(iter(common))]["NetworkID"]
        inspected = run(["docker", "network", "inspect", "-f", "{{.Driver}}", network_id], timeout=20)
        assert inspected.returncode == 0 and inspected.stdout.strip() == "bridge", "The shared network is not a bridge"

        ping = None
        for _ in range(10):
            ping = run(base + ["exec", "-T", "log_aggregator", "ping", "-c", "1", "-W", "2", "db"], timeout=10)
            if ping.returncode == 0:
                break
            time.sleep(1)
        assert ping is not None and ping.returncode == 0, f"log_aggregator cannot reach db:\n{ping.stdout}\n{ping.stderr}"
    finally:
        run(base + ["down", "--remove-orphans", "-v"], timeout=60)


def test_automate_interactive_backup():
    script_path = "/home/user/run_backup.py"
    tool_path = "/app/interactive_backup.sh"
    target_archive = "/home/user/backups/latest.tar.gz"

    assert os.path.isfile(script_path), f"Missing backup script: {script_path}"
    assert os.access(script_path, os.X_OK), "run_backup.py is not executable"

    if os.path.exists(target_archive):
        os.remove(target_archive)

    token = "backup-" + uuid.uuid4().hex
    marker = "/tmp/backup-invoked-" + uuid.uuid4().hex
    original = open(tool_path, "rb").read()
    original_mode = stat.S_IMODE(os.stat(tool_path).st_mode)

    replacement = f'''#!/bin/bash
echo -n "Initiate backup? (y/n): "
read ans1
[ "$ans1" = "y" ] || {{ echo "Aborted"; exit 1; }}
echo -n "Target volume: "
read ans2
[ "$ans2" = "metrics_db" ] || {{ echo "Invalid volume"; exit 1; }}
echo -n "Max quota (GB): "
read ans3
[ "$ans3" = "500" ] || {{ echo "Invalid quota"; exit 1; }}
printf %s {shlex.quote(token)} > backup.tar.gz
printf invoked > {shlex.quote(marker)}
echo "Backup successful."
'''

    try:
        with open(tool_path, "w") as f:
            f.write(replacement)
        os.chmod(tool_path, 0o755)

        with tempfile.TemporaryDirectory(prefix="backup-cwd-") as workdir:
            result = run(["python3", script_path], cwd=workdir, timeout=30)
            assert result.returncode == 0, f"run_backup.py failed with exit code {result.returncode}\nStdout: {result.stdout}\nStderr: {result.stderr}"
            assert os.path.exists(marker), "run_backup.py did not successfully drive the interactive backup tool"
            assert os.path.isfile(target_archive), f"Backup archive not found at {target_archive} after running script."
            with open(target_archive, "rb") as f:
                assert f.read() == token.encode(), "latest.tar.gz was not the archive produced by the backup tool"
            assert not os.path.exists(os.path.join(workdir, "backup.tar.gz")), "The generated archive was not moved to the required destination"
    finally:
        with open(tool_path, "wb") as f:
            f.write(original)
        os.chmod(tool_path, original_mode)
        if os.path.exists(marker):
            os.remove(marker)


def classify(sanitizer_path, path):
    return run(["python3", sanitizer_path, path], timeout=10).returncode


def test_adversarial_log_sanitizer():
    sanitizer_path = "/home/user/sanitize.py"
    assert os.path.isfile(sanitizer_path), f"Missing sanitizer script: {sanitizer_path}"
    assert os.access(sanitizer_path, os.X_OK), "sanitize.py is not executable"

    clean_dir = "/app/corpora/clean/"
    evil_dir = "/app/corpora/evil/"
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith(".json")]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith(".json")]

    assert len(clean_files) > 0, "No clean files found to test."
    assert len(evil_files) > 0, "No evil files found to test."

    failed_clean = [os.path.basename(p) for p in clean_files if classify(sanitizer_path, p) != 0]
    failed_evil = [os.path.basename(p) for p in evil_files if classify(sanitizer_path, p) != 1]

    error_msg = []
    if failed_evil:
        error_msg.append(f"{len(failed_evil)} of {len(evil_files)} evil bypassed: {', '.join(failed_evil)}")
    if failed_clean:
        error_msg.append(f"{len(failed_clean)} of {len(clean_files)} clean modified/rejected: {', '.join(failed_clean)}")
    assert not error_msg, "Sanitizer failed criteria:\n" + "\n".join(error_msg)

    # Exercise newly generated, randomly named files in one unlabeled directory so
    # classification cannot be inferred from the shipped corpus path or filename.
    rng = random.SystemRandom()
    cases = []
    with tempfile.TemporaryDirectory(prefix="json-inputs-") as case_dir:
        for i in range(24):
            safe_name = "service_" + "".join(rng.choice(string.ascii_letters + string.digits + "_-") for _ in range(18))
            clean = {
                "disk_used": rng.randint(0, 100000),
                "disk_allocated": rng.randint(100001, 500000),
                "container": safe_name,
            }
            path = os.path.join(case_dir, uuid.uuid4().hex + ".json")
            with open(path, "w") as f:
                json.dump(clean, f, indent=(2 if i % 2 else None), separators=None if i % 2 else (",", ":"))
            cases.append((path, 0))

            negative = dict(clean)
            negative["disk_used"] = -rng.randint(1, 100000)
            path = os.path.join(case_dir, uuid.uuid4().hex + ".json")
            with open(path, "w") as f:
                json.dump(negative, f)
            cases.append((path, 1))

            injected = dict(clean)
            injected["container"] = safe_name + "; echo compromised"
            path = os.path.join(case_dir, uuid.uuid4().hex + ".json")
            with open(path, "w") as f:
                json.dump(injected, f, indent=2)
            cases.append((path, 1))

        rng.shuffle(cases)
        failures = []
        for path, expected in cases:
            actual = classify(sanitizer_path, path)
            if actual != expected:
                failures.append((os.path.basename(path), expected, actual))
        assert not failures, f"Sanitizer failed randomized content-based cases: {failures[:10]}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
