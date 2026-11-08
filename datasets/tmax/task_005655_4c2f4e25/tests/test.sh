#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import os
import secrets
import subprocess
import tarfile
from datetime import datetime
from decimal import Decimal
from zoneinfo import ZoneInfo

REPO = "/home/user/finops_pipeline"
BACKUP = "/home/user/backups/raw_backup_latest.tar.gz"


def test_git_repo_exists():
    """Verify that the Git repository was created."""
    git_dir = "/home/user/finops_pipeline/.git"
    assert os.path.isdir(git_dir), f"Git repository not found at {git_dir}"


def test_backup_dir_exists():
    """Verify that the backup directory was created."""
    backup_dir = "/home/user/backups"
    assert os.path.isdir(backup_dir), f"Backup directory not found at {backup_dir}"


def test_pre_commit_hook_exists_and_executable():
    """Verify that the pre-commit hook exists and is executable."""
    hook_path = "/home/user/finops_pipeline/.git/hooks/pre-commit"
    assert os.path.isfile(hook_path), f"pre-commit hook not found at {hook_path}"
    assert os.access(hook_path, os.X_OK), f"pre-commit hook at {hook_path} is not executable"


def test_backup_file_created_and_valid():
    """Verify that the backup tarball was created and contains the CSV file."""
    assert os.path.isfile(BACKUP), f"Backup file not found at {BACKUP}"
    try:
        with tarfile.open(BACKUP, "r:gz") as tar:
            names = tar.getnames()
            assert any(name.endswith("input_billing.csv") for name in names), \
                f"input_billing.csv not found in the backup tarball. Contents: {names}"
    except tarfile.ReadError:
        assert False, f"Backup file {BACKUP} is not a valid gzip-compressed tarball"


def test_network_daily_costs_log_content():
    """Verify that the initial network cost log has the expected data."""
    log_path = os.path.join(REPO, "network_daily_costs.log")
    assert os.path.isfile(log_path), f"Log file not found at {log_path}"
    expected_lines = [
        "2023-10-14: $5.50",
        "2023-10-15: $12.25",
        "2023-10-16: $8.00",
        "2023-10-17: $20.00",
    ]
    with open(log_path) as f:
        actual_lines = [line.strip() for line in f if line.strip()]
    assert actual_lines == expected_lines, \
        f"Content of {log_path} does not match expected output.\nExpected: {expected_lines}\nActual: {actual_lines}"


def test_git_commit_exists():
    """Verify that the initial commit was made with the correct message."""
    try:
        result = subprocess.run(
            ["git", "log", "--oneline"], cwd=REPO,
            capture_output=True, text=True, check=True
        )
        assert "Add initial billing data" in result.stdout, \
            f"Commit message 'Add initial billing data' not found in git log. Log output:\n{result.stdout}"
    except subprocess.CalledProcessError as e:
        assert False, f"Failed to run 'git log' in {REPO}. Error: {e.stderr}"


def _csv_bytes(rows):
    output = io.StringIO(newline="")
    writer = csv.writer(output, lineterminator="\n")
    writer.writerow(["Timestamp", "Service", "Region", "Cost"])
    writer.writerows(rows)
    return output.getvalue().encode("utf-8")


def _expected_lines(files):
    totals = {}
    eastern = ZoneInfo("America/New_York")
    for content in files.values():
        reader = csv.DictReader(io.StringIO(content.decode("utf-8")))
        for row in reader:
            if row["Service"] != "EgressNetwork":
                continue
            timestamp = datetime.fromisoformat(row["Timestamp"].replace("Z", "+00:00"))
            local_date = timestamp.astimezone(eastern).date().isoformat()
            totals[local_date] = totals.get(local_date, Decimal("0")) + Decimal(row["Cost"])
    return [f"{date}: ${totals[date]:.2f}" for date in sorted(totals)]


def test_z_hook_processes_newly_staged_csv_files_and_backs_up_their_contents():
    """Stage novel data and commit it to verify the hook's real behavior."""
    token = secrets.token_hex(8)
    names = [f"billing_probe_a_{token}.csv", f"billing_probe_b_{token}.csv"]

    # Randomized costs prevent a fixed output fixture from satisfying this test.
    cents = [secrets.randbelow(8000) + 101 for _ in range(5)]
    costs = [f"{value // 100}.{value % 100:02d}" for value in cents]
    files = {
        names[0]: _csv_bytes([
            ["2024-03-10T04:30:00Z", "EgressNetwork", "us-east-1", costs[0]],
            ["2024-03-10T05:30:00Z", "EgressNetwork", "us-west-2", costs[1]],
            ["2024-03-10T06:30:00Z", "Compute", "us-east-1", "999.99"],
            ["2024-03-10T07:00:00Z", "EgressNetworkExtra", "us-east-1", "888.88"],
        ]),
        names[1]: _csv_bytes([
            ["2024-03-10T07:30:00Z", "EgressNetwork", "eu-central-1", costs[2]],
            ["2024-11-03T03:30:00Z", "EgressNetwork", "ap-northeast-1", costs[3]],
            ["2024-11-03T04:30:00Z", "EgressNetwork", "ap-south-1", costs[4]],
            ["2024-11-03T05:30:00Z", "EgressNetwork ", "us-east-1", "777.77"],
        ]),
    }
    expected = _expected_lines(files)

    subprocess.run(["git", "config", "--global", "--add", "safe.directory", REPO], check=True)
    subprocess.run(["git", "reset", "--quiet", "HEAD", "--", "."], cwd=REPO, check=True)
    for name, content in files.items():
        with open(os.path.join(REPO, name), "wb") as f:
            f.write(content)
    subprocess.run(["git", "add", "--", *names], cwd=REPO, check=True)

    env = os.environ.copy()
    env.update({
        "GIT_AUTHOR_NAME": "Verifier",
        "GIT_AUTHOR_EMAIL": "verifier@example.invalid",
        "GIT_COMMITTER_NAME": "Verifier",
        "GIT_COMMITTER_EMAIL": "verifier@example.invalid",
    })
    result = subprocess.run(
        ["git", "commit", "-m", f"Verifier pipeline probe {token}"],
        cwd=REPO, env=env, capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, \
        f"Commit did not successfully run the pre-commit hook.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"

    log_path = os.path.join(REPO, "network_daily_costs.log")
    assert os.path.isfile(log_path), "Hook did not create network_daily_costs.log"
    with open(log_path) as f:
        actual = [line.strip() for line in f if line.strip()]
    assert actual == expected, \
        f"Hook produced incorrect results for newly staged CSV files.\nExpected: {expected}\nActual: {actual}"

    assert os.path.isfile(BACKUP), "Hook did not create the backup tarball for the new commit"
    try:
        with tarfile.open(BACKUP, "r:gz") as tar:
            csv_members = [m for m in tar.getmembers() if m.isfile() and m.name.lower().endswith(".csv")]
            archived_names = [os.path.basename(m.name) for m in csv_members]
            assert sorted(archived_names) == sorted(names), \
                f"Backup did not contain exactly the staged CSV files. Contents: {[m.name for m in csv_members]}"
            for name, expected_content in files.items():
                matches = [m for m in csv_members if os.path.basename(m.name) == name]
                assert len(matches) == 1, f"Expected one archived member for {name}, found {len(matches)}"
                extracted = tar.extractfile(matches[0])
                assert extracted is not None and extracted.read() == expected_content, \
                    f"Archived content for {name} does not match the staged raw CSV"
    except tarfile.ReadError:
        assert False, f"Backup file {BACKUP} is not a valid gzip-compressed tarball"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
