#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import uuid

BASE = "/home/user/vm_storage"
SCRIPT = "/home/user/validate_configs.py"


def test_vendored_package_fixed():
    """Check that the deliberate bug is fixed and the installed CLI works."""
    sys.path.insert(0, "/app/vendored/qemu-net-builder")
    try:
        from qemu_net_builder.utils import get_subnet
        subnet = get_subnet()
        assert isinstance(subnet, str), f"get_subnet() returned {type(subnet)}, expected str"
        assert subnet == "192.168.100.0", f"Unexpected subnet: {subnet!r}"
    except TypeError as e:
        assert False, f"get_subnet() still raises a TypeError: {e}"
    except ImportError as e:
        assert False, f"Failed to import qemu_net_builder.utils: {e}"
    finally:
        sys.path.pop(0)

    search_path = os.pathsep.join([
        "/home/user/.local/bin",
        "/root/.local/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
    ])
    cli = shutil.which("qemu-net-builder", path=search_path)
    assert cli is not None, "qemu-net-builder CLI is not installed in a normal user PATH"

    env = os.environ.copy()
    env["PATH"] = search_path
    env.pop("PYTHONPATH", None)
    result = subprocess.run(
        [cli], cwd="/tmp", env=env, capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"Installed qemu-net-builder CLI failed: stdout={result.stdout!r}, "
        f"stderr={result.stderr!r}"
    )
    assert result.stdout.strip() == "Network Builder starting on 192.168.100.0"


def run_validator(path):
    return subprocess.run(
        ["/usr/bin/python3", SCRIPT, path],
        capture_output=True,
        text=True,
        timeout=10,
    )


def test_validate_configs_clean_corpus():
    """Keep the original clean-corpus assertions."""
    assert os.path.isfile(SCRIPT), f"Validation script {SCRIPT} not found."
    clean_files = glob.glob("/home/user/corpora/clean/*.json")
    assert len(clean_files) > 0, "No clean corpus files found."

    failed_files = []
    for path in clean_files:
        if run_validator(path).returncode != 0:
            failed_files.append(os.path.basename(path))
    assert not failed_files, (
        f"{len(failed_files)} of {len(clean_files)} clean modified/rejected: "
        f"{', '.join(failed_files)}"
    )


def test_validate_configs_evil_corpus():
    """Keep the original malicious-corpus assertions."""
    assert os.path.isfile(SCRIPT), f"Validation script {SCRIPT} not found."
    evil_files = glob.glob("/home/user/corpora/evil/*.json")
    assert len(evil_files) > 0, "No evil corpus files found."

    bypassed_files = []
    for path in evil_files:
        if run_validator(path).returncode != 1:
            bypassed_files.append(os.path.basename(path))
    assert not bypassed_files, (
        f"{len(bypassed_files)} of {len(evil_files)} evil bypassed: "
        f"{', '.join(bypassed_files)}"
    )


def test_validate_configs_generated_canonical_cases():
    """Exercise containment and symlink resolution using fresh unpredictable paths."""
    assert os.path.isfile(SCRIPT), f"Validation script {SCRIPT} not found."

    token = "verify_" + uuid.uuid4().hex
    inside_root = os.path.join(BASE, token)
    inside_target = os.path.join(inside_root, "target", "data")
    inside_link = os.path.join(inside_root, "inside_link")
    outside_root = tempfile.mkdtemp(prefix=token + "_outside_", dir="/home/user")
    outside_target = os.path.join(outside_root, "secret")
    outside_link = os.path.join(inside_root, "outside_link")
    prefix_sibling = os.path.join("/home/user", "vm_storage_" + token)
    config_dir = tempfile.mkdtemp(prefix="configs_" + uuid.uuid4().hex + "_", dir="/tmp")

    os.makedirs(inside_target)
    os.makedirs(outside_target)
    os.makedirs(prefix_sibling)
    os.symlink(inside_target, inside_link)
    os.symlink(outside_target, outside_link)

    mounts = [
        ".",
        token,
        f"{token}/target/data",
        f"{token}/target/../target/data",
        f"{token}/inside_link",
        f"{token}/inside_link/.",
        f"../{os.path.basename(prefix_sibling)}",
        f"{token}/../../{os.path.basename(outside_root)}",
        f"{token}/outside_link",
        f"{token}/outside_link/secret-child",
    ]

    canonical_base = os.path.realpath(BASE)
    for mount in mounts:
        config_path = os.path.join(config_dir, uuid.uuid4().hex + ".json")
        with open(config_path, "w") as f:
            json.dump({"vm_name": uuid.uuid4().hex, "host_mount": mount}, f)

        resolved = os.path.realpath(os.path.join(BASE, mount))
        try:
            safe = os.path.commonpath([canonical_base, resolved]) == canonical_base
        except ValueError:
            safe = False
        expected = 0 if safe else 1

        result = run_validator(config_path)
        assert result.returncode == expected, (
            f"Validator returned {result.returncode} for generated mount {mount!r}; "
            f"canonical path is {resolved!r}, expected exit {expected}. "
            f"stdout={result.stdout!r}, stderr={result.stderr!r}"
        )


def test_systemd_service_file():
    """Check required text and that directives occur in valid systemd sections."""
    service_file = "/home/user/.config/systemd/user/qemu-net-validator.service"
    assert os.path.isfile(service_file), f"Systemd service file {service_file} is missing."

    with open(service_file, "r") as f:
        content = f.read()

    expected_desc = "Description=QEMU Net Validator"
    expected_exec = "ExecStart=/usr/bin/python3 /home/user/validate_configs.py /home/user/default_config.json"
    expected_restart = "Restart=on-failure"
    assert expected_desc in content, f"'{expected_desc}' not found in service file."
    assert expected_exec in content, f"'{expected_exec}' not found in service file."
    assert expected_restart in content, f"'{expected_restart}' not found in service file."

    sections = {}
    current = None
    for lineno, raw in enumerate(content.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#") or line.startswith(";"):
            continue
        section_match = re.fullmatch(r"\[([^\[\]]+)\]", line)
        if section_match:
            current = section_match.group(1)
            sections.setdefault(current, {})
            continue
        assert current is not None, f"Directive outside a section on line {lineno}"
        assert "=" in line, f"Malformed systemd directive on line {lineno}: {line!r}"
        key, value = line.split("=", 1)
        assert key and not any(ch.isspace() for ch in key), (
            f"Invalid directive name on line {lineno}: {key!r}"
        )
        sections[current].setdefault(key, []).append(value)

    assert sections.get("Unit", {}).get("Description") == ["QEMU Net Validator"]
    assert sections.get("Service", {}).get("ExecStart") == [
        "/usr/bin/python3 /home/user/validate_configs.py /home/user/default_config.json"
    ]
    assert sections.get("Service", {}).get("Restart") == ["on-failure"]
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
