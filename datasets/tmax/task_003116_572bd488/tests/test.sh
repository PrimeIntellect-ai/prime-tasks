#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shlex
import stat
import subprocess
import tempfile
import uuid
from collections import Counter

BIN_PATH = "/home/user/bin/operator"
SRC_PATH = "/home/user/src/operator.c"
LOG_PATH = "/home/user/logs/operator.log"
MANIFESTS_DIR = "/home/user/manifests"


def run_and_check_operator(binary):
    token = uuid.uuid4().hex
    yaml_name = f"audit-{token}.yaml"
    non_yaml_name = f"audit-{token}.txt"
    yaml_path = os.path.join(MANIFESTS_DIR, yaml_name)
    non_yaml_path = os.path.join(MANIFESTS_DIR, non_yaml_name)

    open(yaml_path, "w").close()
    open(non_yaml_path, "w").close()
    try:
        expected_files = sorted(
            name for name in os.listdir(MANIFESTS_DIR)
            if name.endswith(".yaml") and os.path.isfile(os.path.join(MANIFESTS_DIR, name))
        )

        if os.path.exists(LOG_PATH):
            os.remove(LOG_PATH)

        result = subprocess.run([binary], capture_output=True, text=True, timeout=15)
        assert result.returncode == 0, (
            f"Operator binary exited with non-zero status: {result.returncode}; "
            f"stderr: {result.stderr}"
        )
        assert os.path.exists(LOG_PATH), f"Log file {LOG_PATH} was not created."

        with open(LOG_PATH, "r") as f:
            log_content = f.read()
        line_counts = Counter(log_content.splitlines())

        for expected_file in expected_files:
            expected_log = f"[SUCCESS] Deployed {expected_file}"
            assert expected_log in log_content, (
                f"Expected log entry '{expected_log}' not found in {LOG_PATH}."
            )
            assert line_counts[expected_log] >= 1, (
                f"Expected an exact log line '{expected_log}' in {LOG_PATH}."
            )

        unexpected_log = f"[SUCCESS] Deployed {non_yaml_name}"
        assert unexpected_log not in line_counts, "Operator processed a non-YAML file."
    finally:
        for path in (yaml_path, non_yaml_path):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass


def test_operator_binary():
    assert os.path.exists(BIN_PATH), f"Binary {BIN_PATH} does not exist."
    assert os.access(BIN_PATH, os.X_OK), f"Binary {BIN_PATH} is not executable."
    assert os.path.isfile(SRC_PATH), f"Source file {SRC_PATH} does not exist."

    # Exercise the required installed artifact on an unpredictable manifest name.
    run_and_check_operator(BIN_PATH)

    # Also prove that the submitted source itself compiles and has the behavior.
    with tempfile.TemporaryDirectory() as tmpdir:
        compiled = os.path.join(tmpdir, "operator")
        result = subprocess.run(
            ["gcc", SRC_PATH, "-o", compiled], capture_output=True, text=True, timeout=30
        )
        assert result.returncode == 0, f"operator.c failed to compile: {result.stderr}"
        run_and_check_operator(compiled)

    # Preserve the original fixed-manifest assertions as well.
    with open(LOG_PATH, "r") as f:
        log_content = f.read()
    expected_files = ["deployment.yaml", "service.yaml", "ingress.yaml"]
    for expected_file in expected_files:
        if os.path.exists(os.path.join(MANIFESTS_DIR, expected_file)):
            expected_log = f"[SUCCESS] Deployed {expected_file}"
            assert expected_log in log_content, (
                f"Expected log entry '{expected_log}' not found in {LOG_PATH}."
            )


def test_logrotate_conf():
    conf_path = "/home/user/logrotate.conf"
    assert os.path.exists(conf_path), f"Logrotate config {conf_path} does not exist."

    with open(conf_path, "r") as f:
        original = f.read()
    content = original.lower()

    # Original assertions.
    assert "/home/user/logs/operator.log" in content, "Logrotate config missing target log file."
    assert "daily" in content, "Logrotate config missing 'daily' directive."
    assert re.search(r"rotate\s+3", content), "Logrotate config missing 'rotate 3' directive."
    assert "compress" in content, "Logrotate config missing 'compress' directive."
    assert "create" in content, "Logrotate config missing 'create' directive."

    # Ensure logrotate itself accepts the configuration.
    checked = subprocess.run(
        ["logrotate", "--debug", conf_path], capture_output=True, text=True, timeout=20
    )
    assert checked.returncode == 0, f"Invalid logrotate configuration: {checked.stderr}"

    # Strip comments and inspect directives in the stanza that actually targets the log.
    active = "\n".join(line.split("#", 1)[0] for line in original.splitlines())
    matching_bodies = []
    for match in re.finditer(r"([^{}]+)\{([^{}]*)\}", active, flags=re.S):
        header, body = match.groups()
        try:
            targets = shlex.split(header)
        except ValueError as exc:
            raise AssertionError(f"Malformed logrotate stanza header: {exc}")
        if "/home/user/logs/operator.log" in targets:
            matching_bodies.append(body.lower())

    assert matching_bodies, "No active logrotate stanza targets operator.log."
    valid_stanza = False
    for body in matching_bodies:
        directives = []
        for line in body.splitlines():
            line = line.strip()
            if line:
                directives.append(line.split())
        names = [parts[0] for parts in directives]
        rotate_values = [parts[1:] for parts in directives if parts[0] == "rotate"]
        if (
            "daily" in names
            and not any(x in names for x in ("hourly", "weekly", "monthly", "yearly"))
            and ["3"] in rotate_values
            and "compress" in names
            and "nocompress" not in names
            and "create" in names
            and "nocreate" not in names
        ):
            valid_stanza = True
            break
    assert valid_stanza, (
        "The operator.log stanza must actively specify daily, rotate 3, compress, and create."
    )


def test_cron_configuration():
    cron_file = "/home/user/operator.cron"
    assert os.path.exists(cron_file), f"Cron file {cron_file} does not exist."

    with open(cron_file, "r") as f:
        content = f.read()

    cron_pattern = r"\*/5\s+\*\s+\*\s+\*\s+\*\s+/home/user/bin/operator"
    assert re.search(cron_pattern, content), (
        f"Cron file {cron_file} does not contain the correct schedule."
    )

    result = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to read crontab."
    assert re.search(cron_pattern, result.stdout), "Crontab does not contain the correct schedule."


def test_ci_cd_pipeline():
    script_path = "/home/user/build_and_test.sh"
    assert os.path.exists(script_path), f"CI script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"CI script {script_path} is not executable."

    with open(SRC_PATH, "rb") as f:
        source_backup = f.read()
    source_mode = stat.S_IMODE(os.stat(SRC_PATH).st_mode)
    with open(BIN_PATH, "rb") as f:
        binary_backup = f.read()
    binary_mode = stat.S_IMODE(os.stat(BIN_PATH).st_mode)

    token = uuid.uuid4().hex
    marker = f"/tmp/ci-operator-ran-{token}"
    ci_manifest = os.path.join(MANIFESTS_DIR, "ci-test.yaml")
    probe_source = f'''#include <stdio.h>\n#include <unistd.h>\nint main(void) {{\n    if (access("{ci_manifest}", F_OK) != 0) return 7;\n    FILE *log = fopen("{LOG_PATH}", "a");\n    if (!log) return 8;\n    fputs("[SUCCESS] Deployed ci-test.yaml\\n", log);\n    fclose(log);\n    FILE *mark = fopen("{marker}", "w");\n    if (!mark) return 9;\n    fputs("ran", mark);\n    fclose(mark);\n    return 0;\n}}\n'''

    try:
        with open(SRC_PATH, "w") as f:
            f.write(probe_source)
        os.chmod(SRC_PATH, source_mode)
        for path in (BIN_PATH, LOG_PATH, ci_manifest, marker):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass

        result = subprocess.run([script_path], capture_output=True, text=True, timeout=45)
        assert result.returncode == 0, (
            f"CI script exited with non-zero status: {result.returncode}. "
            f"Output: {result.stdout}; stderr: {result.stderr}"
        )
        assert result.stdout.strip() == "CI PASSED", "CI script did not print exactly 'CI PASSED'."
        assert os.path.isfile(BIN_PATH), "CI script did not create the operator binary."
        assert os.access(BIN_PATH, os.X_OK), "CI-created operator binary is not executable."
        assert os.path.isfile(ci_manifest), "CI script did not create ci-test.yaml."
        assert os.path.isfile(marker), (
            "CI script did not compile and execute the program from operator.c."
        )
        assert os.path.exists(LOG_PATH), f"Log file {LOG_PATH} was not created by CI script."
        with open(LOG_PATH, "r") as f:
            log_content = f.read()
        assert "[SUCCESS] Deployed ci-test.yaml" in log_content, (
            "Log file does not contain expected output from CI test."
        )
    finally:
        with open(SRC_PATH, "wb") as f:
            f.write(source_backup)
        os.chmod(SRC_PATH, source_mode)
        with open(BIN_PATH, "wb") as f:
            f.write(binary_backup)
        os.chmod(BIN_PATH, binary_mode)
        try:
            os.remove(marker)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
