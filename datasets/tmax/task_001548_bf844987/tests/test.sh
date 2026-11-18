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
from pathlib import Path

GOLDEN_DATA = {
    "alice": "ENGINEERING",
    "bob": "MARKETING",
    "charlie": "SALES",
    "diana": "ENGINEERING",
    "eve": "HUMAN_RESOURCES",
    "frank": "ENGINEERING",
    "grace": "SALES",
    "heidi": "MARKETING",
    "ivan": "ENGINEERING",
    "judy": "SALES",
}

EXTRACTED = Path("/home/user/extracted_users.txt")
DEPLOY_SCRIPT = Path("/home/user/deploy_users.sh")
ACCOUNTS = Path("/home/user/accounts")


def clear_accounts():
    if os.path.lexists(ACCOUNTS):
        if ACCOUNTS.is_symlink() or not ACCOUNTS.is_dir():
            ACCOUNTS.unlink()
        else:
            shutil.rmtree(ACCOUNTS)


def run_deployer():
    result = subprocess.run(
        ["runuser", "-u", "user", "--", "/bin/bash", str(DEPLOY_SCRIPT)],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"deploy_users.sh failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def exact_profile(path, department):
    expected = f'export DEPT="{department}"'.encode()
    content = path.read_bytes()
    return content == expected or content == expected + b"\n"


def test_required_artifacts_extraction_and_dynamic_deployment():
    assert EXTRACTED.exists(), "/home/user/extracted_users.txt is missing"
    assert stat.S_ISREG(EXTRACTED.lstat().st_mode), "extracted_users.txt must be a regular file"
    assert DEPLOY_SCRIPT.exists(), "/home/user/deploy_users.sh is missing"
    assert stat.S_ISREG(DEPLOY_SCRIPT.lstat().st_mode), "deploy_users.sh must be a regular file"

    script_text = DEPLOY_SCRIPT.read_text(encoding="utf-8")
    first_line = script_text.splitlines()[0] if script_text.splitlines() else ""
    assert re.match(r"^#!.*\bbash(?:\s|$)", first_line), "deploy_users.sh must be a Bash script"
    syntax = subprocess.run(
        ["/bin/bash", "-n", str(DEPLOY_SCRIPT)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert syntax.returncode == 0, f"deploy_users.sh has invalid Bash syntax: {syntax.stderr}"

    raw = EXTRACTED.read_bytes()
    text = raw.decode("utf-8")
    lines = text.splitlines()
    assert lines, "extracted_users.txt is empty"
    assert all(re.fullmatch(r"[a-z0-9_]+:[a-z0-9_]+", line) for line in lines), (
        "Every extracted record must be lowercase and use exact username:department format"
    )

    records = [tuple(line.split(":", 1)) for line in lines]
    correct_pairs = {
        (username, department.lower()) for username, department in GOLDEN_DATA.items()
    }
    correct = len(set(records) & correct_pairs)
    extraction_accuracy = correct / max(len(GOLDEN_DATA), len(records))
    assert extraction_accuracy >= 0.85, (
        f"Extraction accuracy is {extraction_accuracy}, below the threshold of 0.85"
    )

    original_stat = EXTRACTED.stat()
    token = secrets.token_hex(6)
    synthetic = [
        (f"verifya{token}", f"quality_{token}"),
        (f"verifyb{token}", f"field_{token}"),
        (f"verifyc{token}", f"support_{token}"),
    ]

    try:
        EXTRACTED.write_text(
            "".join(f"{username}:{department}\n" for username, department in synthetic),
            encoding="utf-8",
        )
        clear_accounts()
        run_deployer()

        for username, department in synthetic:
            directory = ACCOUNTS / username
            profile = directory / ".bash_profile"
            assert directory.is_dir(), f"deploy_users.sh did not create dynamic user {username}"
            assert stat.S_IMODE(directory.stat().st_mode) == 0o750
            assert profile.is_file()
            assert exact_profile(profile, department.upper()), (
                f"Dynamic profile for {username} does not contain exactly the required export"
            )
    finally:
        EXTRACTED.write_bytes(raw)
        os.chmod(EXTRACTED, stat.S_IMODE(original_stat.st_mode))
        os.chown(EXTRACTED, original_stat.st_uid, original_stat.st_gid)
        clear_accounts()
        run_deployer()


def test_deployment_accuracy():
    correct = 0
    total = len(GOLDEN_DATA)

    for user, dept in GOLDEN_DATA.items():
        dir_path = f"/home/user/accounts/{user}"
        profile_path = f"{dir_path}/.bash_profile"

        if os.path.isdir(dir_path):
            # Check permissions 750
            st = os.stat(dir_path)
            perms = stat.S_IMODE(st.st_mode)
            if perms == 0o750:
                if os.path.isfile(profile_path):
                    with open(profile_path, "r") as f:
                        content = f.read().strip()
                    if f'export DEPT="{dept}"' in content:
                        correct += 1

    accuracy = correct / total
    assert accuracy >= 0.85, f"Deployment accuracy is {accuracy}, which is below the threshold of 0.85."


def test_profiles_are_exact_at_required_accuracy():
    correct = 0
    for user, dept in GOLDEN_DATA.items():
        directory = ACCOUNTS / user
        profile = directory / ".bash_profile"
        if (
            directory.is_dir()
            and stat.S_IMODE(directory.stat().st_mode) == 0o750
            and profile.is_file()
            and exact_profile(profile, dept)
        ):
            correct += 1

    accuracy = correct / len(GOLDEN_DATA)
    assert accuracy >= 0.85, (
        f"Exact profile deployment accuracy is {accuracy}, below the threshold of 0.85"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
