#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "yaml:pyyaml"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import random
import sys
import tempfile
import yaml
import pytest


def test_yaml_patcher_installed():
    """Verify the vendored package is repaired, installable, and installed for user."""
    source_dir = "/app/vendored/yaml-patcher-2.1.0"
    setup_path = os.path.join(source_dir, "setup.py")
    assert os.path.isfile(setup_path), f"Expected vendored setup.py at {setup_path}"

    # Exercise the repaired build configuration itself. The original perturbation
    # makes this command fail before setuptools can process the package.
    setup_result = subprocess.run(
        [sys.executable, "setup.py", "--version"],
        cwd=source_dir,
        capture_output=True,
        text=True,
    )
    assert setup_result.returncode == 0, f"Vendored package remains broken: {setup_result.stderr}"
    assert "2.1.0" in setup_result.stdout, "Vendored package version is not 2.1.0"

    # Confirm the repaired vendored source can actually be installed offline.
    with tempfile.TemporaryDirectory() as prefix:
        install_result = subprocess.run(
            [
                sys.executable, "-m", "pip", "install",
                "--no-index", "--no-deps", "--no-build-isolation",
                "--ignore-installed", "--prefix", prefix, source_dir,
            ],
            capture_output=True,
            text=True,
        )
        assert install_result.returncode == 0, (
            "Repaired vendored package is not installable:\n"
            + install_result.stdout + install_result.stderr
        )
        test_bin = os.path.join(prefix, "bin", "yaml-patcher")
        assert os.path.isfile(test_bin) and os.access(test_bin, os.X_OK)
        test_result = subprocess.run([test_bin, "--version"], capture_output=True, text=True)
        assert test_result.returncode == 0
        assert "2.1.0" in test_result.stdout or "2.1.0" in test_result.stderr

    bin_path = "/home/user/.local/bin/yaml-patcher"
    assert os.path.isfile(bin_path), f"Expected yaml-patcher binary at {bin_path}"
    assert os.access(bin_path, os.X_OK), f"yaml-patcher binary at {bin_path} is not executable"

    result = subprocess.run([bin_path, "--version"], capture_output=True, text=True)
    assert result.returncode == 0, f"yaml-patcher --version failed: {result.stderr}"
    assert "2.1.0" in result.stdout or "2.1.0" in result.stderr, "yaml-patcher version is not 2.1.0"

    # Verify package metadata is present in the user's installation, rather than
    # accepting an unrelated executable that merely prints the expected version.
    metadata_result = subprocess.run(
        [
            "runuser", "-u", "user", "--", "env", "HOME=/home/user",
            sys.executable, "-c",
            "import importlib.metadata as m; print(m.version('yaml-patcher'))",
        ],
        capture_output=True,
        text=True,
    )
    assert metadata_result.returncode == 0, (
        "yaml-patcher is not installed as a package for user: " + metadata_result.stderr
    )
    assert metadata_result.stdout.strip() == "2.1.0"


def test_systemd_service():
    """Verify systemd service and script."""
    script_path = "/home/user/watch.sh"
    assert os.path.isfile(script_path), f"Watch script {script_path} does not exist"
    assert os.access(script_path, os.X_OK), f"Watch script {script_path} is not executable"

    service_path = "/home/user/.config/systemd/user/manifest-watcher.service"
    assert os.path.isfile(service_path), f"Systemd service file {service_path} does not exist"

    enabled_path = "/home/user/.config/systemd/user/default.target.wants/manifest-watcher.service"
    try:
        res = subprocess.run(
            ["systemctl", "--user", "is-enabled", "manifest-watcher.service"],
            capture_output=True,
            text=True,
        )
        if res.returncode == 0 and "enabled" in res.stdout:
            return
    except Exception:
        pass

    assert os.path.islink(enabled_path) or os.path.isfile(enabled_path), \
        "Service is not enabled (missing symlink in default.target.wants)"


def generate_random_deployment(seed):
    """Generate a random Kubernetes Deployment YAML."""
    random.seed(seed)
    name = f"app-{random.randint(1000, 9999)}"
    num_containers = random.randint(1, 5)

    containers = []
    for i in range(num_containers):
        container = {
            "name": f"container-{i}",
            "image": f"nginx:{random.choice(['latest', '1.19', '1.20'])}",
        }
        if random.random() > 0.5:
            container["volumeMounts"] = [
                {"name": "audit-vault", "mountPath": "/var/log/audit"}
            ]
        containers.append(container)

    deployment = {
        "apiVersion": "apps/v1",
        "kind": "Deployment",
        "metadata": {"name": name},
        "spec": {
            "replicas": random.randint(1, 3),
            "template": {
                "metadata": {"labels": {"app": name}},
                "spec": {"containers": containers},
            },
        },
    }

    if random.random() > 0.5:
        deployment["spec"]["template"]["spec"]["volumes"] = [
            {"name": "audit-vault", "emptyDir": {}}
        ]

    return yaml.dump(deployment)


def test_manifest_processor_fuzz_equivalence():
    """Verify bit-exact equivalence against the separately shipped oracle."""
    agent_prog = "/home/user/manifest-processor"
    oracle_prog = "/tests/manifest-processor-oracle"

    assert os.path.isfile(agent_prog), f"Agent program {agent_prog} does not exist"
    assert os.access(agent_prog, os.X_OK), f"Agent program {agent_prog} is not executable"
    assert os.path.isfile(oracle_prog), f"Oracle program {oracle_prog} does not exist"

    for i in range(100):
        input_yaml = generate_random_deployment(i)

        oracle_proc = subprocess.run(
            [sys.executable, oracle_prog],
            input=input_yaml,
            capture_output=True,
            text=True,
        )
        assert oracle_proc.returncode == 0, (
            f"Oracle failed on input {i}:\n{input_yaml}\nError: {oracle_proc.stderr}"
        )
        oracle_out = oracle_proc.stdout

        agent_proc = subprocess.run(
            [agent_prog],
            input=input_yaml,
            capture_output=True,
            text=True,
        )
        assert agent_proc.returncode == 0, (
            f"Agent program failed on input {i}:\n{input_yaml}\nError: {agent_proc.stderr}"
        )
        agent_out = agent_proc.stdout

        if agent_out != oracle_out:
            pytest.fail(
                f"Mismatch on input {i}!\n\n"
                f"INPUT:\n{input_yaml}\n\n"
                f"ORACLE OUTPUT:\n{oracle_out}\n\n"
                f"AGENT OUTPUT:\n{agent_out}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
