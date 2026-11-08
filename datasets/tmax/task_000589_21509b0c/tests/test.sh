#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.machinery
import json
import os
import pathlib
import pwd
import re
import shlex
import subprocess
import time

import pytest

USER = "user"
USER_INFO = pwd.getpwnam(USER)
UID = USER_INFO.pw_uid
HOME = USER_INFO.pw_dir
RUNTIME_DIR = f"/run/user/{UID}"
SERVICE = "fast-exporter.service"
INPUT = "/home/user/app_logs/input.log"
METRICS = "/home/user/metrics.json"


def user_systemctl(*args, check=True):
    env = f"XDG_RUNTIME_DIR={shlex.quote(RUNTIME_DIR)} DBUS_SESSION_BUS_ADDRESS=unix:path={shlex.quote(RUNTIME_DIR + '/bus')}"
    command = env + " systemctl --user " + " ".join(shlex.quote(a) for a in args)
    return subprocess.run(
        ["su", USER, "-s", "/bin/bash", "-c", command],
        check=check,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )


def service_file():
    result = user_systemctl("show", SERVICE, "-p", "FragmentPath", "--value", check=False)
    candidate = result.stdout.strip()
    if result.returncode == 0 and candidate and os.path.isfile(candidate):
        return os.path.realpath(candidate)

    for candidate in (
        f"{HOME}/.config/systemd/user/{SERVICE}",
        f"/etc/systemd/user/{SERVICE}",
        f"/usr/lib/systemd/user/{SERVICE}",
        f"/lib/systemd/user/{SERVICE}",
    ):
        if os.path.isfile(candidate):
            return os.path.realpath(candidate)
    pytest.fail(f"No installed systemd user unit found for {SERVICE}")


def test_solution_ready():
    assert os.path.exists("/home/user/solution_ready.txt"), \
        "Agent did not finish: /home/user/solution_ready.txt is missing"


def test_acls_correct():
    result = subprocess.run(
        ["getfacl", "-cp", "/home/user/app_logs"],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
    )
    entries = set(line.strip() for line in result.stdout.splitlines() if line.strip())

    assert "user::rwx" in entries, "Directory owner does not have usable read/write access"
    assert "default:user::r--" in entries or "default:user:user:r--" in entries, \
        "Default ACLs do not grant new files r-- permissions for user"


def test_cython_extension_is_built_and_installed():
    setup_text = pathlib.Path("/app/fast-metric-exporter/setup.py").read_text()
    assert "parser.pyx" in setup_text and "cythonize" in setup_text, \
        "setup.py does not configure parser.pyx as a Cython extension"
    assert not re.search(r"ext_modules\s*=\s*\[\s*\]", setup_text), \
        "setup.py still has an empty ext_modules configuration"

    code = r'''
import importlib.machinery, json, os, parser
origin = os.path.realpath(parser.__file__)
is_extension = any(origin.endswith(s) for s in importlib.machinery.EXTENSION_SUFFIXES)
result = parser.parse_logs("/home/user/app_logs/input.log")
print(json.dumps({"origin": origin, "is_extension": is_extension, "result": result}))
'''
    result = subprocess.run(
        ["su", USER, "-s", "/bin/bash", "-c", f"cd /tmp && python3 -c {shlex.quote(code)}"],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    info = json.loads(result.stdout.strip().splitlines()[-1])
    assert info["is_extension"], f"Imported parser is not a compiled extension: {info['origin']}"
    assert not info["origin"].startswith("/app/fast-metric-exporter/"), \
        "parser extension was only built in the source tree, not installed for use"


def test_service_configuration_and_enablement():
    unit_path = service_file()
    unit_text = pathlib.Path(unit_path).read_text()

    assert re.search(r"(?mi)^\s*Environment\s*=.*(?:^|[\"' ])TZ=Asia/Tokyo(?:[\"' ]|$)", unit_text), \
        "Service does not set TZ=Asia/Tokyo"

    exec_lines = re.findall(r"(?mi)^\s*ExecStart\s*=\s*(.+)$", unit_text)
    assert exec_lines, "Service has no ExecStart"
    argv = shlex.split(exec_lines[-1].strip())
    assert argv, "Service ExecStart is empty"
    executable = argv[0].lstrip("-@:+!")
    executable = executable.replace("%h", HOME)
    assert os.path.basename(executable) == "fast-metric-exporter", \
        "Service does not execute the installed fast-metric-exporter binary"
    assert os.path.isabs(executable) and os.path.isfile(executable) and os.access(executable, os.X_OK), \
        f"ExecStart exporter is missing or not executable: {executable}"
    assert not os.path.realpath(executable).startswith("/app/fast-metric-exporter/"), \
        "Service executes the vendored source directly rather than an installed binary"

    exporter_text = pathlib.Path(executable).read_text(errors="ignore")
    assert "parser.parse_logs" in exporter_text, \
        "Installed exporter does not invoke the parser extension"
    assert INPUT in exporter_text or INPUT in argv[1:], \
        "Installed exporter is not configured to read input.log"
    assert METRICS in exporter_text or METRICS in argv[1:], \
        "Installed exporter is not configured to write metrics.json"

    enabled = user_systemctl("is-enabled", SERVICE, check=False)
    assert enabled.returncode == 0 and enabled.stdout.strip() == "enabled", \
        f"{SERVICE} is not enabled: {enabled.stdout.strip()} {enabled.stderr.strip()}"


def test_service_performance_and_correctness_on_500000_lines():
    expected_lines = 500000
    os.makedirs(os.path.dirname(INPUT), exist_ok=True)

    with open(INPUT, "w", buffering=1024 * 1024) as logfile:
        for i in range(expected_lines):
            logfile.write(f'2030-01-02T03:04:{i % 60:02d}+09:00 GET /request/{i} 200\n')

    os.chown(INPUT, UID, USER_INFO.pw_gid)
    actual_lines = 0
    with open(INPUT, "rb") as logfile:
        for block in iter(lambda: logfile.read(1024 * 1024), b""):
            actual_lines += block.count(b"\n")
    assert actual_lines == expected_lines, "Verifier failed to create the required test input"

    if os.path.lexists(METRICS):
        os.remove(METRICS)

    start_time = time.monotonic()
    result = user_systemctl("restart", SERVICE, check=False)
    assert result.returncode == 0, \
        f"Failed to restart {SERVICE}: {result.stdout} {result.stderr}"

    data = None
    deadline = start_time + 3.0
    while time.monotonic() <= deadline:
        try:
            with open(METRICS) as metrics_file:
                candidate = json.load(metrics_file)
            if isinstance(candidate, dict):
                data = candidate
                break
        except (FileNotFoundError, json.JSONDecodeError, OSError):
            pass
        time.sleep(0.02)

    runtime = time.monotonic() - start_time
    assert data is not None, \
        f"Service did not produce valid metrics.json within 3.0 seconds (elapsed {runtime:.2f}s)"
    assert runtime <= 3.0, \
        f"Performance threshold not met: runtime was {runtime:.2f}s, expected <= 3.0s"
    assert data.get("timezone_parsed") is True, \
        "Timezone parsing failed. Locale/TZ is not set properly in the service environment."
    assert data.get("lines") == actual_lines, \
        f"Reported line count {data.get('lines')!r} does not match generated input count {actual_lines}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
