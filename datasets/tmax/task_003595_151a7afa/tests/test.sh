#!/bin/bash
set -e
mkdir -p /logs/verifier

BACKUP_DIR=$(mktemp -d)
cp -a /home/user/webroot "$BACKUP_DIR/webroot"
cp -a /home/user/baseline.sha256 "$BACKUP_DIR/baseline.sha256"
cp -a /home/user/csp.txt "$BACKUP_DIR/csp.txt"

restore_inputs() {
    set +e
    rm -rf /home/user/webroot
    cp -a "$BACKUP_DIR/webroot" /home/user/webroot
    cp -a "$BACKUP_DIR/baseline.sha256" /home/user/baseline.sha256
    cp -a "$BACKUP_DIR/csp.txt" /home/user/csp.txt
    rm -rf "$BACKUP_DIR"
}
trap restore_inputs EXIT

# Restore the intended permission state before exercising the submission.
find /home/user/webroot -type f -exec chmod 644 {} +
chmod 777 /home/user/webroot/db_config.ini

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import shutil
import stat
import subprocess
import tempfile

import pytest

SCRIPT = "/home/user/investigate.py"
REPORT = "/home/user/incident_report.json"
WEBROOT = "/home/user/webroot"
BASELINE = "/home/user/baseline.sha256"
CSP = "/home/user/csp.txt"


def run_submission():
    try:
        result = subprocess.run(
            ["python3", SCRIPT],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("/home/user/investigate.py timed out.")
    assert result.returncode == 0, (
        f"/home/user/investigate.py exited with status {result.returncode}. "
        f"stderr: {result.stderr}"
    )


def load_report():
    try:
        with open(REPORT, "r") as f:
            return json.load(f)
    except json.JSONDecodeError:
        pytest.fail("/home/user/incident_report.json is not a valid JSON file.")
    except Exception as e:
        pytest.fail(f"Failed to read /home/user/incident_report.json: {e}")


def test_investigate_script_exists():
    assert os.path.isfile(SCRIPT), "The script /home/user/investigate.py was not found."


def test_investigate_script_executes_and_generates_report():
    # A prewritten report must not satisfy the verifier: the submitted script
    # must recreate it successfully.
    if os.path.lexists(REPORT):
        os.remove(REPORT)
    run_submission()
    assert os.path.isfile(REPORT), "The script did not generate /home/user/incident_report.json."


def test_incident_report_exists():
    assert os.path.isfile(REPORT), "The report /home/user/incident_report.json was not found."


def test_incident_report_content():
    report = load_report()

    # 1. Compromised File
    assert "compromised_file" in report, "Missing 'compromised_file' key in the JSON report."
    expected_compromised = "/home/user/webroot/login.html"
    assert report["compromised_file"] == expected_compromised, f"Incorrect compromised_file. Expected {expected_compromised}, got {report['compromised_file']}."

    # 2. XSS Target URL
    assert "xss_target_url" in report, "Missing 'xss_target_url' key in the JSON report."
    url = report["xss_target_url"]
    # Accept the base URL or the URL with query parameters
    assert url.startswith("https://evil-exfil.net/steal"), f"Incorrect xss_target_url. Expected it to start with 'https://evil-exfil.net/steal', got '{url}'."

    # 3. World Writable File
    assert "world_writable_file" in report, "Missing 'world_writable_file' key in the JSON report."
    expected_writable = "/home/user/webroot/db_config.ini"
    assert report["world_writable_file"] == expected_writable, f"Incorrect world_writable_file. Expected {expected_writable}, got {report['world_writable_file']}."

    # 4. CSP Bypassed
    assert "csp_bypassed" in report, "Missing 'csp_bypassed' key in the JSON report."
    assert report["csp_bypassed"] is True, f"Incorrect csp_bypassed. Expected True, got {report['csp_bypassed']}."


def test_script_performs_analysis_on_changed_inputs():
    saved = tempfile.mkdtemp(prefix="investigate-verifier-")
    saved_webroot = os.path.join(saved, "webroot")
    shutil.copytree(WEBROOT, saved_webroot, copy_function=shutil.copy2)
    shutil.copy2(BASELINE, os.path.join(saved, "baseline.sha256"))
    shutil.copy2(CSP, os.path.join(saved, "csp.txt"))
    report_existed = os.path.exists(REPORT)
    if report_existed:
        shutil.copy2(REPORT, os.path.join(saved, "incident_report.json"))

    try:
        shutil.rmtree(WEBROOT)
        os.makedirs(WEBROOT)

        clean_files = {
            "home.html": "<html><body>Alternate portal</body></html>\n",
            "client.js": "console.log('clean alternate application');\n",
            "settings.ini": "[service]\nkey=alternate\n",
            "notes.txt": "incident test fixture\n",
        }
        for name, content in clean_files.items():
            path = os.path.join(WEBROOT, name)
            with open(path, "w") as f:
                f.write(content)
            os.chmod(path, 0o644)

        with open(BASELINE, "w") as baseline:
            for name in sorted(clean_files):
                path = os.path.join(WEBROOT, name)
                with open(path, "rb") as f:
                    digest = hashlib.sha256(f.read()).hexdigest()
                baseline.write(f"{digest}  {path}\n")

        compromised = os.path.join(WEBROOT, "client.js")
        target = "https://telemetry.example.org/collect"
        with open(compromised, "a") as f:
            f.write(f'fetch("{target}");\n')

        writable = os.path.join(WEBROOT, "notes.txt")
        os.chmod(writable, 0o777)
        assert stat.S_IMODE(os.stat(writable).st_mode) == 0o777

        with open(CSP, "w") as f:
            f.write("Content-Security-Policy: default-src 'self'; script-src 'self' https://telemetry.example.org; object-src 'none';\n")

        if os.path.lexists(REPORT):
            os.remove(REPORT)
        run_submission()
        report = load_report()

        assert report.get("compromised_file") == compromised, (
            "The script did not derive the modified file from the changed baseline and webroot."
        )
        assert isinstance(report.get("xss_target_url"), str) and report["xss_target_url"].startswith(target), (
            "The script did not extract the changed fetch target URL."
        )
        assert report.get("world_writable_file") == writable, (
            "The script did not derive the changed 777-permission file."
        )
        assert report.get("csp_bypassed") is False, (
            "The script did not recognize that the changed target origin is explicitly allowed by script-src."
        )
    finally:
        shutil.rmtree(WEBROOT, ignore_errors=True)
        shutil.copytree(saved_webroot, WEBROOT, copy_function=shutil.copy2)
        shutil.copy2(os.path.join(saved, "baseline.sha256"), BASELINE)
        shutil.copy2(os.path.join(saved, "csp.txt"), CSP)
        if report_existed:
            shutil.copy2(os.path.join(saved, "incident_report.json"), REPORT)
        elif os.path.lexists(REPORT):
            os.remove(REPORT)
        shutil.rmtree(saved, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
