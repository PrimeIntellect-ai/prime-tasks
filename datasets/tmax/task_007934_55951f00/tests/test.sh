#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shlex
import shutil
import subprocess
import uuid
from contextlib import contextmanager

SCRIPT_PATH = "/home/user/cost-analyzer.sh"
CLI_PATH = "/home/user/bin/cloud-cost-cli"
REPORT_PATH = "/home/user/reports/daily_cost.log"
CLEAN_ENV = {"PATH": "/usr/bin:/bin"}


def run_script():
    return subprocess.run(["bash", SCRIPT_PATH], env=CLEAN_ENV, capture_output=True)


def remove_path(path):
    if os.path.isdir(path) and not os.path.islink(path):
        shutil.rmtree(path)
    elif os.path.lexists(path):
        os.remove(path)


@contextmanager
def mocked_cli(body):
    backup = CLI_PATH + ".verifier-backup-" + uuid.uuid4().hex
    existed = os.path.lexists(CLI_PATH)
    if existed:
        os.rename(CLI_PATH, backup)

    try:
        with open(CLI_PATH, "w") as f:
            f.write(body)
        os.chmod(CLI_PATH, 0o755)
        yield
    finally:
        remove_path(CLI_PATH)
        if existed:
            os.rename(backup, CLI_PATH)


@contextmanager
def missing_cli():
    backup = CLI_PATH + ".verifier-missing-" + uuid.uuid4().hex
    existed = os.path.lexists(CLI_PATH)
    if existed:
        os.rename(CLI_PATH, backup)
    try:
        yield
    finally:
        remove_path(CLI_PATH)
        if existed:
            os.rename(backup, CLI_PATH)


def cli_body(csv_lines, marker, exit_code=0):
    quoted_lines = " ".join(shlex.quote(line) for line in csv_lines)
    return (
        "#!/bin/bash\n"
        f": > {shlex.quote(marker)}\n"
        f"printf '%s\\n' {quoted_lines}\n"
        f"exit {exit_code}\n"
    )


def test_script_is_an_executable_file():
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a regular file"
    assert os.access(SCRIPT_PATH, os.X_OK), f"{SCRIPT_PATH} is not executable"


def test_script_execution_success():
    """Original fixed-data success assertion, plus proof that the CLI was invoked."""
    marker = "/tmp/cloud-cost-invoked-" + uuid.uuid4().hex
    body = cli_body(
        ["service,cost", "ec2,145.50", "s3,12.00", "rds,89.25"],
        marker,
    )

    try:
        with mocked_cli(body):
            remove_path(REPORT_PATH)
            result = run_script()

            assert result.returncode == 0, (
                f"Script failed with exit code {result.returncode}. "
                f"Stderr: {result.stderr.decode()}"
            )
            assert os.path.exists(marker), "cloud-cost-cli was not executed"
            assert os.path.exists(REPORT_PATH), f"Report file {REPORT_PATH} was not created."

            with open(REPORT_PATH, "r") as f:
                content = f.read().strip()

            assert content == "Total Cost: $246.75", (
                "Report content is incorrect. Expected 'Total Cost: $246.75', "
                f"got '{content}'"
            )
    finally:
        remove_path(marker)


def test_script_error_handling():
    """Original missing-CLI assertion."""
    with missing_cli():
        result = run_script()
        assert result.returncode == 1, (
            "Script should exit with code 1 when CLI is missing, "
            f"but exited with {result.returncode}."
        )


def test_sums_fresh_csv_outputs_in_clean_environment():
    """Exercise multiple unpredictable CSV datasets rather than one fixed total."""
    for _ in range(2):
        while True:
            costs = [secrets.randbelow(9000) + 100 for _ in range(3)]
            total_cents = sum(costs)
            fractional = total_cents % 100
            if 10 <= fractional <= 99 and fractional % 10 != 0:
                break

        rows = ["service,cost"]
        for cents in costs:
            service = "svc_" + secrets.token_hex(5)
            rows.append(f"{service},{cents // 100}.{cents % 100:02d}")

        expected = f"Total Cost: ${total_cents // 100}.{total_cents % 100:02d}"
        marker = "/tmp/cloud-cost-invoked-" + uuid.uuid4().hex

        try:
            with mocked_cli(cli_body(rows, marker)):
                remove_path(REPORT_PATH)
                result = run_script()

                assert result.returncode == 0, (
                    f"Script failed with exit code {result.returncode}. "
                    f"Stderr: {result.stderr.decode()}"
                )
                assert os.path.exists(marker), "cloud-cost-cli was not executed"
                assert os.path.isfile(REPORT_PATH), "The report was not created"
                with open(REPORT_PATH, "r") as f:
                    actual = f.read().strip()
                assert actual == expected, f"Expected '{expected}', got '{actual}'"
        finally:
            remove_path(marker)


def test_nonzero_cli_exit_aborts_without_report():
    """A CLI that emits plausible CSV and then fails must still be treated as failure."""
    marker = "/tmp/cloud-cost-invoked-" + uuid.uuid4().hex
    rows = ["service,cost", "compute,17.41", "storage,8.22"]

    try:
        with mocked_cli(cli_body(rows, marker, exit_code=23)):
            remove_path(REPORT_PATH)
            result = run_script()

            assert os.path.exists(marker), "cloud-cost-cli was not executed"
            assert result.returncode == 1, (
                "Script should exit with code 1 when cloud-cost-cli fails, "
                f"but exited with {result.returncode}."
            )
            assert not os.path.exists(REPORT_PATH), (
                "The report must not be written when cloud-cost-cli returns non-zero"
            )
    finally:
        remove_path(marker)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
