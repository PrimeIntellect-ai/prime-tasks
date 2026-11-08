#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shlex
import socket
import subprocess
import tempfile
import time
from pathlib import Path

import pytest

USER_ENV = os.environ.copy()
USER_ENV["XDG_RUNTIME_DIR"] = "/run/user/1000"
UNIT_DIR = Path("/home/user/.config/systemd/user")


def systemctl(*args):
    return subprocess.run(
        ["systemctl", "--user", *args],
        capture_output=True,
        text=True,
        env=USER_ENV,
    )


def read_unit(name):
    path = UNIT_DIR / name
    assert path.is_file(), f"File {path} is missing."
    return path.read_text()


def unit_values(content, section, key):
    current = None
    values = []
    for raw in content.splitlines():
        line = raw.strip()
        if not line or line.startswith(("#", ";")):
            continue
        if line.startswith("[") and line.endswith("]"):
            current = line[1:-1].strip().lower()
            continue
        if current == section.lower() and "=" in line:
            found_key, value = line.split("=", 1)
            if found_key.strip().lower() == key.lower():
                values.append(value.strip())
    return values


def parse_seconds(value):
    units = {
        "us": 0.000001,
        "ms": 0.001,
        "s": 1,
        "sec": 1,
        "secs": 1,
        "second": 1,
        "seconds": 1,
        "m": 60,
        "min": 60,
        "mins": 60,
        "minute": 60,
        "minutes": 60,
        "h": 3600,
        "hr": 3600,
        "hour": 3600,
        "hours": 3600,
        "d": 86400,
        "day": 86400,
        "days": 86400,
    }
    compact = re.sub(r"\s+", "", value.lower())
    pieces = re.findall(r"([0-9]+(?:\.[0-9]+)?)([a-z]+)", compact)
    if not pieces or "".join(number + unit for number, unit in pieces) != compact:
        return None
    try:
        return sum(float(number) * units[unit] for number, unit in pieces)
    except KeyError:
        return None


def test_systemd_dependency():
    path = "/home/user/.config/systemd/user/profile-backend.service"
    assert os.path.isfile(path), f"File {path} is missing."
    with open(path, "r") as f:
        content = f.read()
    assert "After=stub-net.service" in content, f"Missing 'After=stub-net.service' in {path}."


def test_backend_is_active_and_reachable():
    result = systemctl("is-active", "profile-backend.service")
    assert result.stdout.strip() == "active", (
        f"profile-backend.service is not active: {result.stdout} {result.stderr}"
    )
    response = subprocess.run(
        ["curl", "--fail", "--silent", "--show-error", "--max-time", "5", "http://127.0.0.1:8084/"],
        capture_output=True,
        text=True,
    )
    assert response.returncode == 0, f"Backend is not reachable on port 8084: {response.stderr}"


def test_nginx_configuration():
    path = "/home/user/deploy/nginx.conf"
    assert os.path.isfile(path), f"File {path} is missing."
    with open(path, "r") as f:
        content = f.read()
    assert "proxy_pass http://localhost:8084;" in content or "proxy_pass http://127.0.0.1:8084;" in content, \
        f"Nginx configuration {path} does not contain the correct proxy_pass directive for port 8084."


def test_proxy_connectivity_using_submitted_configuration():
    snippet = Path("/home/user/deploy/nginx.conf").read_text()
    direct = subprocess.run(
        ["curl", "--fail", "--silent", "--show-error", "--max-time", "5", "http://127.0.0.1:8084/"],
        capture_output=True,
    )
    assert direct.returncode == 0, f"Backend request failed: {direct.stderr.decode(errors='replace')}"

    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]

    with tempfile.TemporaryDirectory() as temp_dir:
        config_path = Path(temp_dir) / "nginx-test.conf"
        config_path.write_text(
            "events {}\n"
            "http {\n"
            "  access_log off;\n"
            f"  pid {temp_dir}/nginx.pid;\n"
            "  server {\n"
            f"    listen 127.0.0.1:{port};\n"
            "    location / {\n"
            f"{snippet}\n"
            "    }\n"
            "  }\n"
            "}\n"
        )
        check = subprocess.run(
            ["/usr/sbin/nginx", "-t", "-c", str(config_path)],
            capture_output=True,
            text=True,
        )
        assert check.returncode == 0, f"Submitted Nginx snippet is invalid: {check.stderr}"

        nginx = subprocess.Popen(
            ["/usr/sbin/nginx", "-c", str(config_path), "-g", "daemon off;"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        try:
            proxied = None
            for _ in range(30):
                proxied = subprocess.run(
                    ["curl", "--fail", "--silent", "--show-error", "--max-time", "2", f"http://127.0.0.1:{port}/"],
                    capture_output=True,
                )
                if proxied.returncode == 0:
                    break
                if nginx.poll() is not None:
                    break
                time.sleep(0.1)
            assert proxied is not None and proxied.returncode == 0, (
                "Reverse proxy did not route to the backend: "
                + (proxied.stderr.decode(errors="replace") if proxied else "no response")
            )
            assert proxied.stdout == direct.stdout, "Proxy response does not match the backend response."
        finally:
            nginx.terminate()
            try:
                nginx.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                nginx.kill()
                nginx.communicate()


def test_timer_active():
    try:
        result = systemctl("is-active", "profile-sync.timer")
        assert result.stdout.strip() == "active", "profile-sync.timer is not active."
    except Exception as e:
        pytest.fail(f"Failed to check timer status: {e}")


def test_timer_schedule_service_command_and_enablement():
    timer = read_unit("profile-sync.timer")
    service = read_unit("profile-sync.service")

    linked_units = unit_values(timer, "Timer", "Unit")
    assert not linked_units or linked_units[-1] == "profile-sync.service", (
        "profile-sync.timer must trigger profile-sync.service."
    )

    interval_values = []
    for key in ("OnUnitActiveSec", "OnUnitInactiveSec"):
        interval_values.extend(unit_values(timer, "Timer", key))
    interval_ok = any(parse_seconds(value) == 900 for value in interval_values)

    calendar_ok = False
    for value in unit_values(timer, "Timer", "OnCalendar"):
        normalized = re.sub(r"\s+", " ", value.strip())
        if re.fullmatch(r"(?:\*-\*-\* )?\*:(?:0|00)/15(?::(?:0|00))?", normalized):
            calendar_ok = True
        if re.fullmatch(r"(?:\*-\*-\* )?\*:(?:0,15,30,45|00,15,30,45)(?::(?:0|00))?", normalized):
            calendar_ok = True
    assert interval_ok or calendar_ok, "profile-sync.timer is not configured to run every 15 minutes."

    exec_lines = unit_values(service, "Service", "ExecStart")
    expected = [
        "/home/user/deploy/filter_profiles.sh",
        "/home/user/incoming_profiles/",
        "/home/user/public_profiles/",
    ]
    command_ok = False
    for line in exec_lines:
        try:
            words = shlex.split(line.lstrip("-+!:@"))
        except ValueError:
            continue
        for index in range(len(words) - len(expected) + 1):
            if words[index:index + len(expected)] == expected:
                command_ok = True
    assert command_ok, "profile-sync.service does not execute the filter with the required directories."

    for unit in ("profile-sync.timer", "profile-sync.service"):
        enabled = systemctl("is-enabled", unit)
        assert enabled.stdout.strip() == "enabled", f"{unit} is not enabled: {enabled.stdout} {enabled.stderr}"

    state = systemctl("show", "profile-sync.service", "--property=Result", "--property=ExecMainStartTimestampMonotonic")
    assert state.returncode == 0, f"Could not inspect profile-sync.service: {state.stderr}"
    properties = dict(
        line.split("=", 1) for line in state.stdout.splitlines() if "=" in line
    )
    assert properties.get("Result") == "success", "profile-sync.service has not completed successfully."
    assert properties.get("ExecMainStartTimestampMonotonic", "0") not in ("", "0"), (
        "profile-sync.service has not been started."
    )


def test_adversarial_corpus_filter():
    script_path = "/home/user/deploy/filter_profiles.sh"
    assert os.path.isfile(script_path), f"Script {script_path} is missing."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    token = os.urandom(8).hex()
    clean_profiles = {
        f"clean_{token}.json": f"Alice_{token}",
        "digits.json": "User_0123456789",
        "underscore.json": "___",
    }
    evil_profiles = {
        "semicolon.json": "alice;id",
        "ampersand.json": "alice&whoami",
        "pipe.json": "alice|cat",
        "dollar.json": "alice$(touch /tmp/filter_verifier_pwned)",
        "backtick.json": "alice`touch /tmp/filter_verifier_pwned`",
        "space.json": "alice admin",
        "dash.json": "alice-admin",
        "unicode.json": "aliceé",
    }
    marker = Path("/tmp/filter_verifier_pwned")
    marker.unlink(missing_ok=True)

    with tempfile.TemporaryDirectory() as input_dir, tempfile.TemporaryDirectory() as output_dir:
        input_path = Path(input_dir)
        output_path = Path(output_dir)
        for filename, username in {**clean_profiles, **evil_profiles}.items():
            (input_path / filename).write_text(json.dumps({"username": username, "nonce": token}))
        (input_path / "ignore.txt").write_text(json.dumps({"username": "CleanButNotJson"}))

        result = subprocess.run([script_path, input_dir, output_dir], capture_output=True, text=True, timeout=15)
        assert result.returncode == 0, f"Script failed on generated corpus: {result.stderr}"
        assert not marker.exists(), "A malicious username was executed by the filter."

        produced = set(os.listdir(output_dir))
        assert produced == set(clean_profiles), (
            f"Expected only clean profiles; expected {set(clean_profiles)}, got {produced}"
        )
        for filename in clean_profiles:
            link = output_path / filename
            source = input_path / filename
            assert link.is_symlink(), f"Clean file {filename} was not symlinked."
            assert os.path.samefile(link, source), f"Symlink {filename} does not point to its original input file."


# Retain the original corpus assertions when optional corpora are supplied.
def test_adversarial_corpus_filter_optional_external_corpora():
    script_path = "/home/user/deploy/filter_profiles.sh"
    evil_corpus = "/opt/tests/corpora/evil/"
    clean_corpus = "/opt/tests/corpora/clean/"
    if not os.path.isdir(evil_corpus) or not os.path.isdir(clean_corpus):
        return

    evil_files = [f for f in os.listdir(evil_corpus) if f.endswith(".json")]
    clean_files = [f for f in os.listdir(clean_corpus) if f.endswith(".json")]
    with tempfile.TemporaryDirectory() as temp_out:
        result_evil = subprocess.run([script_path, evil_corpus, temp_out], capture_output=True, text=True)
        assert result_evil.returncode == 0, f"Script failed on evil corpus: {result_evil.stderr}"
        evil_bypassed = os.listdir(temp_out)
        assert len(evil_bypassed) == 0, f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {evil_bypassed}"
    with tempfile.TemporaryDirectory() as temp_out:
        result_clean = subprocess.run([script_path, clean_corpus, temp_out], capture_output=True, text=True)
        assert result_clean.returncode == 0, f"Script failed on clean corpus: {result_clean.stderr}"
        clean_preserved = os.listdir(temp_out)
        clean_modified = set(clean_files) - set(clean_preserved)
        for filename in clean_preserved:
            assert os.path.islink(os.path.join(temp_out, filename)), f"Clean file {filename} was not symlinked."
        assert len(clean_modified) == 0, f"{len(clean_modified)} clean modified/rejected: {list(clean_modified)}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
