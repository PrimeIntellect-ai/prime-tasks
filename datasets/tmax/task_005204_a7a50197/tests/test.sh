#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import configparser
import os
import shlex
import subprocess
import time
import pytest

BASE = "/home/user/netmon"
MAIN_CONF = f"{BASE}/supervisor/supervisord.conf"
PROGRAM_CONF = f"{BASE}/supervisor/conf.d/netmon.conf"
MONITOR = f"{BASE}/bin/monitor.py"
LOG = f"{BASE}/logs/connectivity.log"
PIDFILE = f"{BASE}/run/supervisord.pid"


def supervisorctl(*args):
    return subprocess.run(
        ["supervisorctl", "-c", MAIN_CONF, *args],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=10,
    )


def test_symlink_correct():
    symlink_path = f"{BASE}/config/active.json"
    expected_target = f"{BASE}/config/available/production.json"

    assert os.path.islink(symlink_path), f"'{symlink_path}' is not a symlink."

    actual_target = os.readlink(symlink_path)
    actual_target_abs = os.path.abspath(os.path.join(os.path.dirname(symlink_path), actual_target))
    expected_target_abs = os.path.abspath(expected_target)

    assert actual_target_abs == expected_target_abs, (
        f"Symlink points to '{actual_target}', expected it to point to '{expected_target}'."
    )


def test_autorestart_policy():
    assert os.path.isfile(PROGRAM_CONF), f"Configuration file '{PROGRAM_CONF}' is missing."

    with open(PROGRAM_CONF, "r") as f:
        content = f.read()

    # Retain the original textual assertion.
    assert "autorestart=true" in content.replace(" ", ""), (
        f"'autorestart=true' not found in '{PROGRAM_CONF}'. The service will not restart automatically."
    )

    # Also parse the effective program settings so a comment cannot satisfy the test.
    parser = configparser.RawConfigParser(
        interpolation=None,
        inline_comment_prefixes=("#", ";"),
    )
    parser.read(PROGRAM_CONF)
    assert parser.has_section("program:netmon"), "Missing [program:netmon] section."
    assert parser.has_option("program:netmon", "autorestart"), "Missing effective autorestart setting."
    assert parser.get("program:netmon", "autorestart").strip().lower() == "true", (
        "The effective autorestart setting for netmon is not true."
    )
    assert parser.has_option("program:netmon", "command"), "Missing netmon command."
    assert shlex.split(parser.get("program:netmon", "command")) == [MONITOR], (
        "The supervised netmon command is not the supplied monitoring script."
    )


def test_connectivity_log_success():
    assert os.path.isfile(LOG), f"Log file '{LOG}' has not been created."

    with open(LOG, "r") as f:
        content = f.read()

    assert "STATUS: PING_SUCCESS" in content, (
        f"'STATUS: PING_SUCCESS' not found in '{LOG}'. The monitor script may not be running or the config is wrong."
    )


def test_supervisord_running():
    assert os.path.isfile(PIDFILE), f"Supervisord PID file '{PIDFILE}' not found. Is supervisord running?"

    with open(PIDFILE, "r") as f:
        pid_str = f.read().strip()

    assert pid_str.isdigit(), f"PID file '{PIDFILE}' does not contain a valid PID."
    pid = int(pid_str)

    try:
        os.kill(pid, 0)
    except OSError:
        pytest.fail(f"Supervisord process with PID {pid} is not running.")

    proc_cmdline = f"/proc/{pid}/cmdline"
    assert os.path.isfile(proc_cmdline), f"Cannot inspect process {pid}."
    with open(proc_cmdline, "rb") as f:
        argv = [x.decode(errors="replace") for x in f.read().split(b"\0") if x]

    assert any("supervisord" in os.path.basename(arg) for arg in argv), (
        f"PID {pid} is not a supervisord process: {argv!r}"
    )
    assert "-c" in argv, f"Supervisord was not started with -c: {argv!r}"
    conf_index = argv.index("-c") + 1
    assert conf_index < len(argv), "Supervisord -c option has no configuration path."
    assert os.path.realpath(argv[conf_index]) == os.path.realpath(MAIN_CONF), (
        f"Supervisord is not using '{MAIN_CONF}': {argv!r}"
    )

    status = supervisorctl("status", "netmon")
    assert status.returncode == 0, f"Cannot query netmon through supervisord: {status.stdout}"


def test_monitor_really_runs_and_is_automatically_restarted():
    # Remove all previously supplied evidence, then start the configured program through
    # the running supervisor. The real monitor writes once and crashes, so two distinct
    # monitor PIDs and two new messages demonstrate that supervisord actually restarted it.
    with open(LOG, "w"):
        pass

    restarted = supervisorctl("restart", "netmon")
    assert restarted.returncode == 0, f"Unable to restart netmon through supervisord: {restarted.stdout}"

    validated_pids = set()
    deadline = time.time() + 15
    success_count = 0

    while time.time() < deadline:
        result = supervisorctl("pid", "netmon")
        value = result.stdout.strip()
        if result.returncode == 0 and value.isdigit() and int(value) > 0:
            child_pid = int(value)
            cmdline_path = f"/proc/{child_pid}/cmdline"
            try:
                with open(cmdline_path, "rb") as f:
                    child_argv = [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
                if MONITOR in child_argv:
                    validated_pids.add(child_pid)
            except (FileNotFoundError, ProcessLookupError):
                pass

        try:
            with open(LOG, "r") as f:
                success_count = f.read().count("STATUS: PING_SUCCESS")
        except FileNotFoundError:
            success_count = 0

        if len(validated_pids) >= 2 and success_count >= 2:
            break
        time.sleep(0.1)

    assert len(validated_pids) >= 2, (
        "Did not observe supervisord run and automatically restart the supplied monitor script."
    )
    assert success_count >= 2, (
        "The supervised monitor did not produce fresh PING_SUCCESS messages across restarts."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
