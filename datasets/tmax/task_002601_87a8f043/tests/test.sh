#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import sys
import threading

SCRIPT = "/home/user/deploy.py"
MIGRATION = "/home/user/migration"
CONFIG = "/home/user/migration/config.json"
APP_CURRENT = "/home/user/app_current"
LOG = "/home/user/deploy.log"


def expected_line(version):
    target = os.path.join(MIGRATION, version)
    config_link = os.path.join(target, "config.json")
    return f"DEPLOYED {version} TO {target} WITH CONFIG {config_link}"


def read_log():
    with open(LOG, "r") as f:
        return f.read().splitlines()


def replace_with_symlink(path, target):
    temporary = f"{path}.verifier-{os.getpid()}"
    if os.path.lexists(temporary):
        os.unlink(temporary)
    os.symlink(target, temporary)
    os.replace(temporary, path)


def run_deploy(version):
    before = read_log()
    result = subprocess.run(
        [sys.executable, SCRIPT, version],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=5,
    )
    assert result.returncode == 0, (
        f"deploy.py {version} failed with status {result.returncode}: {result.stderr}"
    )

    target = os.path.join(MIGRATION, version)
    config_link = os.path.join(target, "config.json")
    assert os.path.islink(config_link), f"{config_link} was not created as a symlink"
    assert os.readlink(config_link) == CONFIG
    assert os.path.islink(APP_CURRENT), f"{APP_CURRENT} is not a symlink"
    assert os.readlink(APP_CURRENT) == target

    after = read_log()
    assert len(after) == len(before) + 1, "Each deployment must append exactly one log line"
    assert after[:-1] == before, "Deployment must append to, not replace, the existing log"
    assert after[-1] == expected_line(version)


def test_deploy_script_exists():
    assert os.path.isfile(SCRIPT), f"Deployment script {SCRIPT} is missing."


def test_v2_config_symlink():
    v2_config_symlink = "/home/user/migration/v2/config.json"
    expected_target = "/home/user/migration/config.json"

    assert os.path.islink(v2_config_symlink), f"{v2_config_symlink} is not a symlink. Ensure the script creates this symlink."
    actual_target = os.readlink(v2_config_symlink)
    assert actual_target == expected_target, f"{v2_config_symlink} points to {actual_target}, expected {expected_target}."


def test_app_current_symlink():
    app_current_symlink = "/home/user/app_current"
    expected_target = "/home/user/migration/v2"

    assert os.path.islink(app_current_symlink), f"{app_current_symlink} is not a symlink. Ensure the script updates this symlink atomically."
    actual_target = os.readlink(app_current_symlink)
    assert actual_target == expected_target, f"{app_current_symlink} points to {actual_target}, expected {expected_target}."


def test_deploy_log_updated():
    assert os.path.isfile(LOG), f"Deployment log {LOG} is missing."
    lines = read_log()
    assert len(lines) > 0, f"Deployment log {LOG} is empty."
    expected = "DEPLOYED v2 TO /home/user/migration/v2 WITH CONFIG /home/user/migration/v2/config.json"
    assert lines[-1] == expected, f"The last line of {LOG} was '{lines[-1]}', expected '{expected}'."


def test_script_behavior_arguments_repeatability_and_atomicity():
    # Ensure execution, rather than a pre-created final state, repairs wrong links.
    replace_with_symlink("/home/user/migration/v1/config.json", "/tmp/wrong-config")
    replace_with_symlink(APP_CURRENT, "/tmp/wrong-version")
    run_deploy("v1")

    # Re-deploying the same version must work and append exactly one more line.
    run_deploy("v1")
    run_deploy("v2")

    # Exactly one command-line argument is required, and invalid invocations must
    # not alter deployment state or the log.
    state_before = (
        os.readlink(APP_CURRENT),
        os.readlink("/home/user/migration/v2/config.json"),
        read_log(),
    )
    for args in ([], ["v1", "v2"]):
        result = subprocess.run(
            [sys.executable, SCRIPT, *args],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=5,
        )
        assert result.returncode != 0, f"deploy.py must reject argument list {args!r}"
        assert (
            os.readlink(APP_CURRENT),
            os.readlink("/home/user/migration/v2/config.json"),
            read_log(),
        ) == state_before, "An invalid invocation changed deployment state"

    # Continuously observe app_current while repeatedly switching versions. An
    # atomic replacement never exposes a missing, non-symlink, or partial state.
    observation_errors = []
    stop = threading.Event()
    allowed_targets = {
        "/home/user/migration/v1",
        "/home/user/migration/v2",
    }

    def observe():
        while not stop.is_set():
            try:
                mode = os.lstat(APP_CURRENT).st_mode
                if not stat.S_ISLNK(mode):
                    observation_errors.append("app_current was temporarily not a symlink")
                    return
                target = os.readlink(APP_CURRENT)
                if target not in allowed_targets:
                    observation_errors.append(f"app_current exposed unexpected target {target!r}")
                    return
            except FileNotFoundError:
                observation_errors.append("app_current was temporarily missing")
                return
            except OSError as exc:
                observation_errors.append(f"app_current could not be read: {exc}")
                return

    watcher = threading.Thread(target=observe, daemon=True)
    watcher.start()
    try:
        for index in range(100):
            run_deploy("v1" if index % 2 == 0 else "v2")
    finally:
        stop.set()
        watcher.join(timeout=2)

    assert not observation_errors, observation_errors[0]

    # Leave the required final state and verify the original final assertions.
    run_deploy("v2")
    assert os.path.islink("/home/user/migration/v2/config.json")
    assert os.readlink("/home/user/migration/v2/config.json") == CONFIG
    assert os.path.islink(APP_CURRENT)
    assert os.readlink(APP_CURRENT) == "/home/user/migration/v2"
    assert read_log()[-1] == expected_line("v2")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
