#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import stat
import subprocess
import tempfile

APP = "/home/user/app"
USERS_DIR = "/home/user/app/users/"
LOG_FILE = "/home/user/app/quota.log"


def test_service_dependency():
    path = "/home/user/app/account-monitor.service"
    assert os.path.exists(path), f"{path} does not exist."

    with open(path, "r") as f:
        content = f.read()

    # Preserve the original assertion that After is in [Unit].
    unit_section_match = re.search(r'\[Unit\](.*?)(?:\[|$)', content, re.DOTALL)
    assert unit_section_match, "[Unit] section missing in service file."
    unit_section_content = unit_section_match.group(1)
    assert re.search(r'^After\s*=\s*storage-init\.service\s*$', unit_section_content, re.MULTILINE), \
        "The directive 'After=storage-init.service' was not found in the [Unit] section."

    # The only permitted change is one exact added directive line.
    original = (
        "[Unit]\n"
        "Description=Account Monitor Service\n"
        "Wants=storage-init.service\n"
        "\n"
        "[Service]\n"
        "Type=simple\n"
        "ExecStart=/home/user/app/check_quota.sh\n"
        "\n"
        "[Install]\n"
        "WantedBy=default.target\n"
    )
    lines = content.splitlines(keepends=True)
    matching = [i for i, line in enumerate(lines) if line == "After=storage-init.service\n"]
    assert len(matching) == 1, "The service must contain exactly one exact After=storage-init.service line."
    del lines[matching[0]]
    assert "".join(lines) == original, "The rest of account-monitor.service was modified."


def test_auto_provision_expect():
    path = "/home/user/app/auto_provision.exp"
    provision = "/home/user/app/provision.sh"
    assert os.path.exists(path), f"{path} does not exist."
    assert os.path.isfile(path), f"{path} is not a regular file."
    assert os.access(path, os.X_OK), f"{path} is not executable."

    with open(path, "rb") as f:
        first_line = f.readline().decode("utf-8", "replace").strip()
    assert re.match(r'^#!\s*(?:/usr/bin/expect|/usr/bin/env\s+expect)(?:\s|$)', first_line), \
        "auto_provision.exp must be an Expect script."

    # Temporarily substitute an equivalent interactive provisioner and record the
    # actual responses. This proves the Expect artifact invokes the required path
    # and handles its prompts rather than merely printing the success text.
    with open(provision, "rb") as f:
        original_data = f.read()
    original_mode = stat.S_IMODE(os.stat(provision).st_mode)
    nonce = secrets.token_hex(16)
    record = f"/tmp/provision-input-{nonce}"
    challenge = f'''#!/bin/bash
printf 'Enter Admin PIN: '
IFS= read -r pin || exit 91
printf 'Action (1=Init, 2=Clear): '
IFS= read -r action || exit 92
printf '%s\\n%s\\n' "$pin" "$action" > '{record}'
if [ "$pin" = '8821' ] && [ "$action" = '1' ]; then
    echo 'Initialization complete.'
    exit 0
fi
echo 'Invalid provisioning input.'
exit 1
'''.encode()

    try:
        with open(provision, "wb") as f:
            f.write(challenge)
        os.chmod(provision, 0o755)
        result = subprocess.run([path], capture_output=True, text=True, timeout=15)
        assert result.returncode == 0, \
            f"auto_provision.exp failed with return code {result.returncode}. Output: {result.stderr}"
        assert "Initialization complete." in result.stdout, \
            "auto_provision.exp did not output the expected success message."
        assert os.path.exists(record), \
            "auto_provision.exp did not execute /home/user/app/provision.sh."
        with open(record, "r") as f:
            supplied = f.read().splitlines()
        assert supplied == ["8821", "1"], \
            f"Expected PIN 8821 and Action 1, but provision.sh received: {supplied!r}"
    finally:
        with open(provision, "wb") as f:
            f.write(original_data)
        os.chmod(provision, original_mode)
        try:
            os.remove(record)
        except FileNotFoundError:
            pass


def reset_users():
    shutil.rmtree(USERS_DIR, ignore_errors=True)
    os.makedirs(USERS_DIR, exist_ok=True)


def run_and_check_append(path, expected):
    before = b""
    if os.path.exists(LOG_FILE):
        with open(LOG_FILE, "rb") as f:
            before = f.read()
    subprocess.run([path], check=True, timeout=15)
    assert os.path.exists(LOG_FILE), f"{LOG_FILE} was not created."
    with open(LOG_FILE, "rb") as f:
        after = f.read()
    assert after.startswith(before), "check_quota.sh overwrote or altered existing quota.log data."
    appended = after[len(before):]
    wanted = (expected + "\n").encode()
    assert appended == wanted, f"Expected exactly {wanted!r} to be appended, got {appended!r}."
    with open(LOG_FILE, "r") as f:
        lines = f.readlines()
    assert len(lines) > 0, f"{LOG_FILE} is empty."
    assert lines[-1].strip() == expected


def actual_du_size():
    result = subprocess.run(
        ["du", "-sb", USERS_DIR], capture_output=True, text=True, check=True
    )
    return int(result.stdout.split()[0])


def create_random_tree_with_exact_size(target):
    reset_users()
    rng = secrets.SystemRandom()
    nested = os.path.join(USERS_DIR, "group-" + secrets.token_hex(4))
    os.makedirs(nested)
    for _ in range(rng.randint(2, 5)):
        name = "data-" + secrets.token_hex(5)
        size = rng.randint(20, 250)
        with open(os.path.join(nested, name), "wb") as f:
            f.write(os.urandom(size))
    ballast = os.path.join(USERS_DIR, "ballast-" + secrets.token_hex(4))
    with open(ballast, "wb"):
        pass

    # du -sb reports apparent file sizes plus directory entries. Tune a file from
    # the verifier's own du result so boundary expectations are derived, not fixed.
    for _ in range(4):
        current = actual_du_size()
        delta = target - current
        assert delta >= 0, f"Test tree unexpectedly exceeded target {target}."
        new_size = os.path.getsize(ballast) + delta
        with open(ballast, "r+b") as f:
            f.truncate(new_size)
        if actual_du_size() == target:
            break
    assert actual_du_size() == target, f"Could not construct a du size of exactly {target}."


def test_check_quota_script():
    path = "/home/user/app/check_quota.sh"
    assert os.path.exists(path), f"{path} does not exist."
    assert os.path.isfile(path), f"{path} is not a regular file."
    assert os.access(path, os.X_OK), f"{path} is not executable."
    with open(path, "rb") as f:
        first_line = f.readline().decode("utf-8", "replace").strip()
    assert re.match(r'^#!\s*(?:/bin/bash|/usr/bin/bash|/usr/bin/env\s+bash)(?:\s|$)', first_line), \
        "check_quota.sh must be a bash script."

    # Start with a deterministic log, then retain the original under/over checks.
    with open(LOG_FILE, "wb"):
        pass
    reset_users()
    with open(os.path.join(USERS_DIR, "smallfile"), "wb") as f:
        f.write(b"0" * 1024)
    run_and_check_append(path, "OK")

    with open(os.path.join(USERS_DIR, "largefile"), "wb") as f:
        f.write(b"0" * 15000)
    run_and_check_append(path, "QUOTA_EXCEEDED")

    # Exercise unpredictable directory layouts and both sides of the strict
    # boundary, including exactly 10000 and exactly 10001 bytes.
    rng = secrets.SystemRandom()
    targets = [
        rng.randint(3000, 8500),
        rng.randint(8501, 9999),
        10000,
        10001,
        rng.randint(10002, 18000),
    ]
    rng.shuffle(targets)
    for target in targets:
        create_random_tree_with_exact_size(target)
        measured = actual_du_size()
        expected = "QUOTA_EXCEEDED" if measured > 10000 else "OK"
        run_and_check_append(path, expected)


def test_crontab():
    result = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to read crontab. Has it been initialized?"

    found = False
    for line in result.stdout.splitlines():
        if re.match(r'^\s*\*/5\s+\*\s+\*\s+\*\s+\*\s+/home/user/app/check_quota\.sh\s*$', line):
            found = True
            break
    assert found, "Crontab entry for check_quota.sh with schedule '*/5 * * * *' was not found."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
