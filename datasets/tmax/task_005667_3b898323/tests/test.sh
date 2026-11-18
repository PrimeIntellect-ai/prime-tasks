#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shlex
import shutil
import subprocess
import tempfile
import uuid
from datetime import datetime
from zoneinfo import ZoneInfo

import pytest


@pytest.fixture(scope="session", autouse=True)
def execute_and_validate_artifacts():
    runner = "/home/user/run_job.sh"
    mailer = "/home/user/app/mailer.go"
    assert os.path.isfile(runner), f"File {runner} is missing."
    assert os.path.isfile(mailer), f"File {mailer} is missing."

    real_go = shutil.which("go")
    assert real_go, "The Go executable is unavailable."

    # Exercise mailer.go with verifier-derived values and a fresh output path.
    probe_root = tempfile.mkdtemp(prefix="mailer_probe_")
    probe_reports = os.path.join(probe_root, "reports_" + uuid.uuid4().hex)
    probe_port = str(30000 + (uuid.uuid4().int % 20000))
    fallback_report = "/tmp/default_reports/report.txt"
    shutil.rmtree("/tmp/default_reports", ignore_errors=True)

    probe_env = os.environ.copy()
    probe_env.update({
        "REPORTS_DIR": probe_reports,
        "TZ": "UTC",
        "LC_ALL": "C.UTF-8",
        "SMTP_PORT": probe_port,
    })
    subprocess.run(
        [real_go, "run", mailer],
        cwd="/home/user/app",
        env=probe_env,
        check=True,
        timeout=120,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    probe_report = os.path.join(probe_reports, "report.txt")
    assert os.path.isfile(probe_report), "mailer.go did not use the supplied REPORTS_DIR."
    assert not os.path.exists(fallback_report), "mailer.go still wrote to the fallback report directory."
    with open(probe_report, "r", encoding="utf-8") as f:
        probe_content = f.read()
    assert re.fullmatch(
        rf"Time: \d{{4}}-\d{{2}}-\d{{2}} \d{{2}}:\d{{2}}:\d{{2}} UTC\nLocale: C\.UTF-8\nPort: {re.escape(probe_port)}\n",
        probe_content,
    ), "mailer.go did not preserve the required report formatting or environment values."

    # Run the required runner from a clean state. A transparent Go wrapper records
    # the environment that run_job.sh actually supplies to the Go invocation.
    report_path = "/home/user/reports/report.txt"
    try:
        os.remove(report_path)
    except FileNotFoundError:
        pass
    shutil.rmtree("/tmp/default_reports", ignore_errors=True)

    wrapper_dir = tempfile.mkdtemp(prefix="go_wrapper_")
    capture_path = os.path.join(wrapper_dir, "captured_env.json")
    wrapper_path = os.path.join(wrapper_dir, "go")
    with open(wrapper_path, "w", encoding="utf-8") as f:
        f.write("#!/bin/bash\n")
        f.write("python3 - <<'PY'\n")
        f.write("import json, os\n")
        f.write("with open(os.environ['VERIFIER_ENV_CAPTURE'], 'w') as out:\n")
        f.write("    json.dump({k: os.environ.get(k) for k in ['REPORTS_DIR', 'TZ', 'LC_ALL', 'SMTP_PORT']}, out)\n")
        f.write("PY\n")
        f.write("exec " + shlex.quote(real_go) + " \"$@\"\n")
    os.chmod(wrapper_path, 0o755)

    run_env = os.environ.copy()
    run_env["PATH"] = wrapper_dir + os.pathsep + run_env.get("PATH", "")
    run_env["VERIFIER_ENV_CAPTURE"] = capture_path
    subprocess.run(
        [runner],
        env=run_env,
        check=True,
        timeout=120,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    assert os.path.isfile(capture_path), "run_job.sh did not execute the Go program through its environment."
    with open(capture_path, "r", encoding="utf-8") as f:
        captured = json.load(f)
    assert captured == {
        "REPORTS_DIR": "/home/user/reports",
        "TZ": "America/Los_Angeles",
        "LC_ALL": "en_US.UTF-8",
        "SMTP_PORT": "2525",
    }, "run_job.sh did not export the required values to the Go process."
    assert not os.path.exists(fallback_report), "The required job wrote a report to the fallback directory."


def test_runner_contains_exports():
    path = "/home/user/run_job.sh"
    with open(path, "r", encoding="utf-8") as f:
        lines = f.readlines()

    exported = set()
    for line in lines:
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or not re.match(r"^export(?:\s|$)", stripped):
            continue
        try:
            tokens = shlex.split(stripped, comments=True)
        except ValueError:
            continue
        for token in tokens[1:]:
            if token == ";":
                break
            exported.add(token.split("=", 1)[0])

    for name in ("REPORTS_DIR", "TZ", "LC_ALL", "SMTP_PORT"):
        assert name in exported, f"{name} is not exported in run_job.sh."


def test_report_file_exists():
    path = "/home/user/reports/report.txt"
    assert os.path.isfile(path), f"Expected report file {path} does not exist. Did the job run successfully and write to the correct directory?"


def test_report_file_content():
    path = "/home/user/reports/report.txt"
    assert os.path.isfile(path), f"Expected report file {path} does not exist."

    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    assert "Locale: en_US.UTF-8" in content, "The report file does not contain the correct Locale. Ensure LC_ALL is exported correctly."
    assert "Port: 2525" in content, "The report file does not contain the correct Port. Ensure SMTP_PORT is exported correctly."
    assert "PST" in content or "PDT" in content, "The report file does not contain the correct timezone indicator (PST/PDT). Ensure TZ is exported correctly."

    match = re.fullmatch(
        r"Time: (\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) (PST|PDT)\nLocale: en_US\.UTF-8\nPort: 2525\n",
        content,
    )
    assert match, "The generated report does not have the required formatting."
    reported = datetime.strptime(match.group(1), "%Y-%m-%d %H:%M:%S")
    current_la = datetime.now(ZoneInfo("America/Los_Angeles")).replace(tzinfo=None)
    assert abs((current_la - reported).total_seconds()) < 180, "The report was not freshly generated in the requested timezone."


def test_smtp_config_content():
    path = "/home/user/config/smtp.json"
    assert os.path.isfile(path), f"Configuration file {path} does not exist."

    with open(path, "r", encoding="utf-8") as f:
        try:
            config = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} does not contain valid JSON.")

    expected_config = {
        "mailing_list": "active",
        "protocol": "smtp"
    }
    assert config == expected_config, f"The contents of {path} do not exactly match the required JSON structure."


def test_mailer_go_fixed():
    path = "/home/user/app/mailer.go"
    assert os.path.isfile(path), f"File {path} is missing."

    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    assert "repDir := envDir" not in content, "The variable shadowing bug in mailer.go has not been fixed."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
