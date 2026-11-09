#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess

ACCOUNTS_FILE = "/home/user/accounts.txt"
FSTAB_FILE = "/home/user/custom_fstab"
SCRIPT_FILE = "/home/user/setup_mounts.sh"

ORIGINAL_ACCOUNTS = b"""alice:engineering:101
bob:sales:102
charlie:engineering:103
diana:hr:104
"""

ORIGINAL_FSTAB = b"""/dev/sda1 / ext4 defaults 1 1
# Other system mounts
/dev/sdb1 /home ext4 defaults 1 2
"""

EXPECTED_ACCOUNTS = [
    ("alice", "engineering"),
    ("bob", "sales"),
    ("charlie", "engineering"),
    ("diana", "hr"),
]


def get_accounts():
    accounts = []
    if not os.path.exists(ACCOUNTS_FILE):
        return accounts
    with open(ACCOUNTS_FILE, "r") as f:
        for line in f:
            line = line.strip()
            if line:
                parts = line.split(":")
                if len(parts) >= 2:
                    accounts.append((parts[0], parts[1]))
    return accounts


def mount_line(username):
    return f"/home/user/global_share /home/user/site_users/{username}/shared_data none bind 0 0"


def remove_mount_lines(content, mounts):
    mount_bytes = {mount.encode() for mount in mounts}
    return b"".join(
        line for line in content.splitlines(keepends=True)
        if line.rstrip(b"\r\n") not in mount_bytes
    )


def assert_mount_state(content, mounts, unrelated_content):
    text_lines = [line.strip() for line in content.decode().splitlines() if line.strip()]
    for mount in mounts:
        count = text_lines.count(mount)
        assert count == 1, f"Expected exactly 1 occurrence of '{mount}', found {count}."
    assert remove_mount_lines(content, mounts) == unrelated_content, \
        "Unrelated fstab content was added, removed, reordered, or modified."


def run_script():
    subprocess.run([SCRIPT_FILE], check=True, timeout=15)


def test_original_accounts_are_intact():
    assert os.path.isfile(ACCOUNTS_FILE), f"{ACCOUNTS_FILE} is missing."
    with open(ACCOUNTS_FILE, "rb") as f:
        assert f.read() == ORIGINAL_ACCOUNTS, \
            "accounts.txt must retain all four original records unchanged."
    assert get_accounts() == EXPECTED_ACCOUNTS


def test_directories_and_symlinks():
    accounts = get_accounts()
    assert len(accounts) > 0, "/home/user/accounts.txt is missing or empty."

    for username, department in accounts:
        base_dir = f"/home/user/site_users/{username}"
        workspace = os.path.join(base_dir, "workspace")
        shared_data = os.path.join(base_dir, "shared_data")
        dept_link = os.path.join(base_dir, "dept_link")

        assert os.path.isdir(workspace), f"Workspace directory missing for {username}: {workspace}"
        assert os.path.isdir(shared_data), f"Shared data directory missing for {username}: {shared_data}"
        assert os.path.islink(dept_link), f"Symlink missing for {username}: {dept_link}"

        target = os.readlink(dept_link)
        expected_target = f"/home/user/departments/{department}"
        assert target == expected_target, \
            f"Symlink for {username} points to {target}, expected {expected_target}"


def test_report_content():
    report_file = "/home/user/report.txt"
    assert os.path.isfile(report_file), f"Report file {report_file} is missing."

    accounts = get_accounts()
    expected_lines = sorted([f"{u} -> {d}" for u, d in accounts])
    with open(report_file, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, "Report file content does not match expected output."


def test_fstab_and_script_idempotency_and_behavior():
    assert os.path.isfile(FSTAB_FILE), f"fstab file {FSTAB_FILE} is missing."
    assert os.path.isfile(SCRIPT_FILE), f"Script {SCRIPT_FILE} is missing."
    assert os.access(SCRIPT_FILE, os.X_OK), f"Script {SCRIPT_FILE} is not executable."

    accounts = get_accounts()
    expected_mounts = [mount_line(u) for u, _ in accounts]

    with open(FSTAB_FILE, "rb") as f:
        initial_content = f.read()

    # Keep the original assertions that the supplied mount lines survived.
    decoded_initial = initial_content.decode()
    assert "/dev/sda1 / ext4 defaults 1 1" in decoded_initial, \
        "Original fstab lines were removed or modified."
    assert "/dev/sdb1 /home ext4 defaults 1 2" in decoded_initial, \
        "Original fstab lines were removed or modified."

    # The requested mounts must already be populated exactly once, and every byte
    # of unrelated original content must remain unchanged.
    assert_mount_state(initial_content, expected_mounts, ORIGINAL_FSTAB)

    # Remove the requested entries before execution. This proves the script itself
    # performs the updates instead of accepting manually pre-populated output.
    with open(FSTAB_FILE, "wb") as f:
        f.write(ORIGINAL_FSTAB)
    run_script()
    with open(FSTAB_FILE, "rb") as f:
        after_first_run = f.read()
    assert_mount_state(after_first_run, expected_mounts, ORIGINAL_FSTAB)

    # Running again must leave the complete file byte-for-byte unchanged.
    run_script()
    with open(FSTAB_FILE, "rb") as f:
        after_second_run = f.read()
    assert after_second_run == after_first_run, \
        "Script is not idempotent or modifies unrelated fstab content on repeated execution."

    # Exercise the script with records chosen by the verifier so a hard-coded or
    # no-op implementation cannot pass. Preserve and restore the required state.
    saved_accounts = ORIGINAL_ACCOUNTS
    saved_fstab = after_second_run
    dynamic_accounts = b"zoe:engineering:901\nmike:sales:902\n"
    dynamic_mounts = [mount_line("zoe"), mount_line("mike")]
    dynamic_unrelated = b"# verifier preservation probe\n/dev/test /probe ext4 ro 0 0\n"
    preexisting_zoe = (dynamic_mounts[0] + "\n").encode()

    try:
        with open(ACCOUNTS_FILE, "wb") as f:
            f.write(dynamic_accounts)
        with open(FSTAB_FILE, "wb") as f:
            f.write(dynamic_unrelated + preexisting_zoe)

        run_script()
        with open(FSTAB_FILE, "rb") as f:
            dynamic_first = f.read()
        assert_mount_state(dynamic_first, dynamic_mounts, dynamic_unrelated)

        run_script()
        with open(FSTAB_FILE, "rb") as f:
            dynamic_second = f.read()
        assert dynamic_second == dynamic_first, \
            "Script is not idempotent for accounts read at execution time."
    finally:
        with open(ACCOUNTS_FILE, "wb") as f:
            f.write(saved_accounts)
        with open(FSTAB_FILE, "wb") as f:
            f.write(saved_fstab)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
