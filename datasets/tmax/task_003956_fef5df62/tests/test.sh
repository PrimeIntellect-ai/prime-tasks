#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import pwd
import secrets
import stat
import subprocess
import tempfile

import pytest

HOME = "/home/user"
SOURCE = f"{HOME}/src/exporter.go"
DEPLOY = f"{HOME}/deploy.sh"
BINARY = f"{HOME}/bin/exporter"
LOG = f"{HOME}/data/requests.log"
SUMMARY = f"{HOME}/metrics/summary.json"
SERVICE = f"{HOME}/.config/systemd/user/exporter.service"
TIMER = f"{HOME}/.config/systemd/user/exporter.timer"
UID = pwd.getpwnam("user").pw_uid
USER_ENV = [f"HOME={HOME}", f"XDG_RUNTIME_DIR=/run/user/{UID}"]


def run_as_user(argv, **kwargs):
    return subprocess.run(
        ["runuser", "-u", "user", "--", "env", *USER_ENV, *argv],
        **kwargs,
    )


def file_hash(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def deployment_snapshot():
    return {
        path: (file_hash(path), stat.S_IMODE(os.stat(path).st_mode))
        for path in (BINARY, SERVICE, TIMER)
    }


def parse_unit(path):
    sections = {}
    current = None
    with open(path, encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith(("#", ";")):
                continue
            if line.startswith("[") and line.endswith("]"):
                current = line[1:-1].strip()
                sections.setdefault(current, {})
                continue
            assert current is not None and "=" in line, f"Invalid unit-file line in {path}: {raw!r}"
            key, value = line.split("=", 1)
            sections[current].setdefault(key.strip(), []).append(value.strip())
    return sections


def systemctl_user(*args):
    return run_as_user(
        ["systemctl", "--user", *args], capture_output=True, text=True, timeout=30
    )


def test_exporter_go_exists():
    assert os.path.isfile(SOURCE), f"{SOURCE} does not exist."


def test_deploy_script_idempotent():
    assert os.path.isfile(DEPLOY), f"{DEPLOY} does not exist."
    assert os.access(DEPLOY, os.X_OK), f"{DEPLOY} is not executable."
    with open(DEPLOY, "rb") as f:
        first_line = f.readline()
    assert first_line.startswith(b"#!") and b"bash" in first_line, f"{DEPLOY} is not a bash script."

    first = run_as_user([DEPLOY], capture_output=True, text=True, timeout=120)
    assert first.returncode == 0, f"{DEPLOY} failed: {first.stderr}"
    before = deployment_snapshot()

    second = run_as_user([DEPLOY], capture_output=True, text=True, timeout=120)
    assert second.returncode == 0, f"{DEPLOY} failed on subsequent run: {second.stderr}"
    assert deployment_snapshot() == before, "Repeated deployment changed generated artifacts or their modes."


def test_exporter_binary_executable_and_built_from_source():
    assert os.path.isfile(BINARY), f"{BINARY} does not exist."
    assert os.access(BINARY, os.X_OK), f"{BINARY} is not executable."

    go_info = subprocess.run(["go", "version", "-m", BINARY], capture_output=True, text=True)
    assert go_info.returncode == 0, f"{BINARY} is not a Go executable: {go_info.stderr}"

    with tempfile.TemporaryDirectory() as tmp:
        os.chown(tmp, UID, pwd.getpwnam("user").pw_gid)
        reference = os.path.join(tmp, "exporter-from-source")
        built = run_as_user(
            ["go", "build", "-o", reference, SOURCE],
            capture_output=True,
            text=True,
            timeout=120,
        )
        assert built.returncode == 0, f"Compiling {SOURCE} failed: {built.stderr}"
        assert file_hash(BINARY) == file_hash(reference), (
            f"{BINARY} is not the executable produced from {SOURCE}."
        )


def test_metrics_directory_permissions():
    metrics_dir = f"{HOME}/metrics"
    assert os.path.isdir(metrics_dir), f"{metrics_dir} does not exist."
    assert stat.S_IMODE(os.stat(metrics_dir).st_mode) == 0o700, (
        f"Permissions for {metrics_dir} are not 700 (drwx------)."
    )


def test_exporter_output_json_on_dynamic_inputs():
    original_log = open(LOG, "rb").read() if os.path.exists(LOG) else None
    original_summary = open(SUMMARY, "rb").read() if os.path.exists(SUMMARY) else None
    rng = secrets.SystemRandom()

    try:
        for iteration in range(3):
            codes = rng.sample(range(201, 599), 4)
            counts = {str(code): rng.randint(1, 7) for code in codes}
            lines = []
            timestamp = rng.randint(1700000000, 1900000000)
            for code, count in counts.items():
                for n in range(count):
                    lines.append(f"{timestamp} {code} /verify/{iteration}/{code}/{n}\n")
                    timestamp += rng.randint(1, 9)
            rng.shuffle(lines)
            log_contents = "".join(lines)
            with open(LOG, "w", encoding="utf-8") as f:
                f.write(log_contents)
            with open(SUMMARY, "w", encoding="utf-8") as f:
                json.dump({"stale": 999999}, f)

            result = run_as_user([BINARY], capture_output=True, text=True, timeout=30)
            assert result.returncode == 0, f"Running {BINARY} failed: {result.stderr}"
            assert os.path.isfile(SUMMARY), f"{SUMMARY} was not generated."
            assert open(LOG, encoding="utf-8").read() == log_contents, "Exporter modified its input log."

            try:
                with open(SUMMARY, encoding="utf-8") as f:
                    data = json.load(f)
            except json.JSONDecodeError as exc:
                pytest.fail(f"{SUMMARY} does not contain valid JSON: {exc}")

            assert isinstance(data, dict), "Summary JSON is not an object."
            assert all(isinstance(k, str) and type(v) is int for k, v in data.items()), (
                "Summary keys must be strings and counts must be JSON integers."
            )
            assert data == counts, f"JSON output {data} does not match expected {counts}."
    finally:
        if original_log is None:
            if os.path.exists(LOG):
                os.unlink(LOG)
        else:
            with open(LOG, "wb") as f:
                f.write(original_log)
        if original_summary is None:
            if os.path.exists(SUMMARY):
                os.unlink(SUMMARY)
        else:
            with open(SUMMARY, "wb") as f:
                f.write(original_summary)


def test_systemd_service_file():
    assert os.path.isfile(SERVICE), f"{SERVICE} does not exist."
    unit = parse_unit(SERVICE)
    assert unit.get("Unit", {}).get("Description") == ["Custom Metrics Exporter"], (
        "Service file has an incorrect Description."
    )
    assert unit.get("Service", {}).get("Type") == ["oneshot"], (
        "Service file has an incorrect Type."
    )
    assert unit.get("Service", {}).get("ExecStart") == [BINARY], (
        "Service file has an incorrect ExecStart."
    )


def test_systemd_timer_file_and_lifecycle():
    assert os.path.isfile(TIMER), f"{TIMER} does not exist."
    unit = parse_unit(TIMER)
    assert unit.get("Unit", {}).get("Description") == ["Run Exporter Every Minute"], (
        "Timer file has an incorrect Description."
    )
    assert unit.get("Timer", {}).get("OnCalendar") == ["*-*-* *:*:00"], (
        "Timer file has an incorrect OnCalendar."
    )

    enabled = systemctl_user("is-enabled", "exporter.timer")
    assert enabled.returncode == 0 and enabled.stdout.strip() == "enabled", (
        f"exporter.timer is not enabled: {enabled.stdout}{enabled.stderr}"
    )
    active = systemctl_user("is-active", "exporter.timer")
    assert active.returncode == 0 and active.stdout.strip() == "active", (
        f"exporter.timer is not running: {active.stdout}{active.stderr}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
