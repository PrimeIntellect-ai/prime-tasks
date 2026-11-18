#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import sys
import tarfile

RAW_LOG = "/home/user/backup_jobs.log"
REDACTED_LOG = "/home/user/redacted.log"
PROCESS_SCRIPT = "/home/user/process_backups.py"
SUCCESS_IDS = "/home/user/successful_job_ids.txt"
TARBALL = "/home/user/backup_report.tar.gz"


def test_redacted_log():
    assert os.path.exists(REDACTED_LOG), f"{REDACTED_LOG} does not exist."
    assert os.path.isfile(REDACTED_LOG), f"{REDACTED_LOG} is not a file."

    with open(REDACTED_LOG, "r") as f:
        content = f.read()
    with open(RAW_LOG, "r") as f:
        source = f.read()

    ipv4 = r"(?:[0-9]{1,3}\.){3}[0-9]{1,3}"
    expected = re.sub(
        rf"(?m)^(ServerIP:[ \t]*){ipv4}(?=[ \t]*$)",
        lambda match: match.group(1) + "XXX.XXX.XXX.XXX",
        source,
    )
    assert content == expected, "redacted.log is not an exact redacted transformation of backup_jobs.log."

    assert "192.168.1.10" not in content, "Real IP 192.168.1.10 was not redacted."
    assert "10.0.0.55" not in content, "Real IP 10.0.0.55 was not redacted."
    assert "172.16.254.1" not in content, "Real IP 172.16.254.1 was not redacted."

    lines = content.strip().split("\n")
    server_ip_lines = [line for line in lines if line.startswith("ServerIP:")]
    assert len(server_ip_lines) == 4, "Expected 4 ServerIP lines in the redacted log."
    for line in server_ip_lines:
        assert line == "ServerIP: XXX.XXX.XXX.XXX", f"Invalid redaction format: {line}"


def test_successful_job_ids():
    assert os.path.exists(PROCESS_SCRIPT), f"{PROCESS_SCRIPT} does not exist."
    assert os.path.isfile(PROCESS_SCRIPT), f"{PROCESS_SCRIPT} is not a file."

    result = subprocess.run(
        [sys.executable, "-I", PROCESS_SCRIPT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"{PROCESS_SCRIPT} failed when executed. stdout={result.stdout!r}, stderr={result.stderr!r}"
    )

    assert os.path.exists(SUCCESS_IDS), f"{SUCCESS_IDS} does not exist."
    assert os.path.isfile(SUCCESS_IDS), f"{SUCCESS_IDS} is not a file."

    with open(SUCCESS_IDS, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_ids = ["1041", "1045", "1048"]
    assert lines == expected_ids, f"Expected successful job IDs {expected_ids}, got {lines}"


def test_tarball_archive():
    assert os.path.exists(TARBALL), f"{TARBALL} does not exist."
    assert os.path.isfile(TARBALL), f"{TARBALL} is not a file."
    assert tarfile.is_tarfile(TARBALL), f"{TARBALL} is not a valid tar archive."

    with tarfile.open(TARBALL, "r:gz") as tar:
        members = tar.getmembers()
        assert len(members) == 1, f"Expected exactly 1 file in tarball, found {len(members)}."

        member = members[0]
        assert member.name == "successful_job_ids.txt", f"Expected file named 'successful_job_ids.txt' at root of tarball, got '{member.name}'."

        f = tar.extractfile(member)
        assert f is not None, "Could not extract file from tarball."
        content = f.read().decode("utf-8")

        lines = [line.strip() for line in content.split("\n") if line.strip()]
        expected_ids = ["1041", "1045", "1048"]
        assert lines == expected_ids, f"Tarball content mismatch. Expected {expected_ids}, got {lines}"


def test_parser_on_unpredictable_records():
    rng = secrets.SystemRandom()
    ids = rng.sample(range(20000, 90000), 8)
    statuses = ["SUCCESS"] * 4 + ["FAILED"] * 4
    rng.shuffle(statuses)
    records = list(zip(ids, statuses))
    rng.shuffle(records)

    chunks = []
    for index, (job_id, status) in enumerate(records):
        lines = [
            "[JOB_START]",
            f"JobID: {job_id}",
            "ServerIP: XXX.XXX.XXX.XXX",
            f"Result: {status}",
            f"FilesProcessed: {rng.randrange(0, 50000)}",
        ]
        if status == "FAILED":
            lines.extend([
                f"ErrorTrace: generated failure {index}",
                f"at generated.module.worker{index}(worker.py:{rng.randrange(1, 500)})",
            ])
        lines.append("[JOB_END]")
        chunks.append("\n".join(lines))

    dynamic_log = "\n".join(chunks) + "\n"
    expected = [str(job_id) for job_id, status in records if status == "SUCCESS"]
    expected.sort(key=int)

    saved_redacted = open(REDACTED_LOG, "rb").read()
    saved_success = open(SUCCESS_IDS, "rb").read() if os.path.exists(SUCCESS_IDS) else None
    try:
        with open(REDACTED_LOG, "w") as f:
            f.write(dynamic_log)
        if os.path.exists(SUCCESS_IDS):
            os.unlink(SUCCESS_IDS)

        result = subprocess.run(
            [sys.executable, "-I", PROCESS_SCRIPT],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, (
            f"Parser failed on generated records. stdout={result.stdout!r}, stderr={result.stderr!r}"
        )
        assert os.path.isfile(SUCCESS_IDS), "Parser did not create successful_job_ids.txt."
        with open(SUCCESS_IDS, "r") as f:
            actual = f.read().splitlines()
        assert all(re.fullmatch(r"[0-9]+", line) for line in actual), (
            "successful_job_ids.txt must contain exactly one integer per line."
        )
        assert actual == expected, f"Generated-record result mismatch: expected {expected}, got {actual}"
    finally:
        with open(REDACTED_LOG, "wb") as f:
            f.write(saved_redacted)
        if saved_success is None:
            if os.path.exists(SUCCESS_IDS):
                os.unlink(SUCCESS_IDS)
        else:
            with open(SUCCESS_IDS, "wb") as f:
                f.write(saved_success)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
