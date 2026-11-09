#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import string
import subprocess

SCRIPT_PATH = "/home/user/deploy_system.sh"
CONFIG_PATH = "/home/user/services.conf"
LOCK_DIR = "/home/user/locks"
LOG_PATH = "/home/user/diagnostics.log"

ORIGINAL_CONFIG = """# Core Services Configuration
web=enabled
db=enabled  # Database service requires special parsing
cache=disabled
api=enabled # API gateway
"""


def run_script():
    result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True)
    assert result.returncode == 0, (
        f"deploy_system.sh failed with return code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )


def actual_locks():
    assert os.path.isdir(LOCK_DIR), f"Directory {LOCK_DIR} does not exist."
    return {name for name in os.listdir(LOCK_DIR) if name.endswith(".lock")}


def expected_locks_from_config(contents):
    expected = set()
    for raw_line in contents.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        name, status = line.split("=", 1)
        name = name.strip()
        status = status.split("#", 1)[0].rstrip()
        if status == "enabled":
            expected.add(f"{name}.lock")
    return expected


def random_name(prefix):
    suffix = "".join(random.SystemRandom().choice(string.ascii_lowercase) for _ in range(12))
    return f"{prefix}_{suffix}"


def test_deployment_and_parsing_behavior():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."

    with open(CONFIG_PATH, "r") as f:
        assert f.read() == ORIGINAL_CONFIG, "services.conf was changed."

    with open(SCRIPT_PATH, "r") as f:
        script_source = f.read()
    expected_assignments = re.findall(
        r"(?m)^[ \t]*EXPECTED_ENABLED[ \t]*=[ \t]*([0-9]+)[ \t]*(?:#.*)?$",
        script_source,
    )
    assert expected_assignments and all(value == "3" for value in expected_assignments), (
        "EXPECTED_ENABLED must remain set to 3."
    )

    # Preserve all original checks against the shipped fixture.
    run_script()
    assert actual_locks() == {"api.lock", "db.lock", "web.lock"}, (
        f"Expected locks {{'api.lock', 'db.lock', 'web.lock'}}, but found {actual_locks()}."
    )
    assert os.path.isfile(LOG_PATH), f"Diagnostics log {LOG_PATH} does not exist."
    with open(LOG_PATH, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]
    expected_lines = [
        "/home/user/locks/api.lock",
        "/home/user/locks/db.lock",
        "/home/user/locks/web.lock",
    ]
    assert actual_lines == expected_lines, (
        "Diagnostics log contents are incorrect.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )

    # Exercise parsing with unpredictable service names and independently derive
    # the required lock set from each generated configuration.
    generated_configs = []
    for _ in range(2):
        enabled_names = [random_name("svc") for _ in range(3)]
        disabled_names = [random_name("off") for _ in range(2)]
        lines = [
            "# generated configuration",
            "",
            f"{enabled_names[0]}=enabled  # inline comment",
            f"{disabled_names[0]}=disabled # the word enabled here is only a comment",
            f"{enabled_names[1]}=enabled\t# tab before comment",
            f"{enabled_names[2]}=enabled      ",
            f"{disabled_names[1]}=disabled     ",
            "# another pure comment",
        ]
        random.SystemRandom().shuffle(lines)
        generated_configs.append("\n".join(lines) + "\n")

    try:
        for contents in generated_configs:
            with open(CONFIG_PATH, "w") as f:
                f.write(contents)

            for name in os.listdir(LOCK_DIR):
                if name.endswith(".lock"):
                    os.unlink(os.path.join(LOCK_DIR, name))

            run_script()
            expected = expected_locks_from_config(contents)
            assert len(expected) == 3
            assert actual_locks() == expected, (
                f"Parser produced wrong locks for generated configuration. "
                f"Expected {expected}, found {actual_locks()}."
            )
    finally:
        with open(CONFIG_PATH, "w") as f:
            f.write(ORIGINAL_CONFIG)

    # Leave and revalidate the requested final state using the original fixture.
    run_script()
    assert actual_locks() == {"api.lock", "db.lock", "web.lock"}
    assert os.path.isfile(LOG_PATH), f"Diagnostics log {LOG_PATH} does not exist."
    with open(LOG_PATH, "r") as f:
        final_lines = [line.strip() for line in f if line.strip()]
    assert final_lines == expected_lines
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
