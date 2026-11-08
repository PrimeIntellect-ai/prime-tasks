#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import contextlib
import json
import os
import random
import re
import stat
import string
import subprocess
import tempfile
import pytest

ORACLE_PATH = "/app/loc_masker"
AGENT_SCRIPT = "/home/user/fast_masker.py"
PARALLEL_SCRIPT = "/home/user/parallel_process.sh"
CRON_FILE = "/home/user/loc_sync.cron"


def generate_random_ip():
    return f"{random.randint(1, 255)}.{random.randint(0, 255)}.{random.randint(0, 255)}.{random.randint(0, 255)}"


def generate_random_email():
    user = "".join(random.choices(string.ascii_lowercase + string.digits, k=random.randint(5, 10)))
    domain = "".join(random.choices(string.ascii_lowercase, k=random.randint(3, 8)))
    tld = "".join(random.choices(string.ascii_lowercase, k=random.randint(2, 3)))
    return f"{user}@{domain}.{tld}"


def generate_random_text():
    chars = string.ascii_letters + string.digits + " \t.,!?"
    fullwidth = "ＡＢＣＤＥＦＧＨＩＪＫＬＭＮＯＰＱＲＳＴＵＶＷＸＹＺａｂｃｄｅｆｇｈｉｊｋｌｍｎｏｐｑｒｓｔｕｖｗｘｙｚ０１２３４５６７８９"
    emojis = "😀😂🚀🌟🎉🔥"
    pool = chars + fullwidth + emojis

    length = random.randint(10, 100)
    text = "".join(random.choices(pool, k=length))

    num_emails = random.randint(0, 2)
    for _ in range(num_emails):
        email = generate_random_email()
        insert_pos = random.randint(0, len(text))
        text = text[:insert_pos] + " " + email + " " + text[insert_pos:]

    return text


def generate_input_json():
    return {
        "timestamp": random.randint(1600000000, 1800000000),
        "locale": random.choice(["en-US", "fr-FR", "es-ES", "zh-CN", "ar-SA"]),
        "original": generate_random_text(),
        "translated": generate_random_text(),
        "editor_ip": generate_random_ip(),
    }


def oracle_output(input_data):
    proc = subprocess.run(
        [ORACLE_PATH],
        input=input_data,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert proc.returncode == 0, f"Oracle failed: {proc.stderr.decode('utf-8', errors='replace')}"
    return proc.stdout


@contextlib.contextmanager
def oracle_blocked_for_agent():
    original_mode = stat.S_IMODE(os.stat(ORACLE_PATH).st_mode)
    os.chmod(ORACLE_PATH, 0)
    try:
        yield
    finally:
        os.chmod(ORACLE_PATH, original_mode)


def run_as_agent_user(argv, input_data=None, timeout=30):
    return subprocess.run(
        ["runuser", "-u", "user", "--"] + argv,
        input=input_data,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )


def test_files_exist():
    assert os.path.isfile(AGENT_SCRIPT), f"Missing Python script: {AGENT_SCRIPT}"
    assert os.path.isfile(PARALLEL_SCRIPT), f"Missing parallel script: {PARALLEL_SCRIPT}"
    assert os.path.isfile(CRON_FILE), f"Missing cron file: {CRON_FILE}"


def test_cron_contents():
    with open(CRON_FILE, "r", encoding="utf-8") as f:
        content = f.read().strip()

    # Preserve the original content assertions.
    assert "2" in content and "0" in content, "Cron file doesn't seem to schedule at 2:00 AM."
    assert PARALLEL_SCRIPT in content, f"Cron file doesn't call {PARALLEL_SCRIPT}."
    assert "/data/events.jsonl" in content, "Cron file missing input file path."
    assert "/data/processed.jsonl" in content, "Cron file missing output redirection."

    active_lines = [
        line.strip() for line in content.splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]
    schedule = re.compile(
        r"^0[ \t]+2[ \t]+\*[ \t]+\*[ \t]+\*[ \t]+"
        r"/home/user/parallel_process\.sh[ \t]+/data/events\.jsonl"
        r"[ \t]*>[ \t]*/data/processed\.jsonl[ \t]*$"
    )
    assert any(schedule.fullmatch(line) for line in active_lines), (
        "Cron file must contain a valid daily 2:00 AM entry with the required command and redirection."
    )


def test_fuzz_equivalence():
    random.seed(42)
    N = 2000

    inputs = [json.dumps(generate_input_json()) for _ in range(N)]
    input_data = ("\n".join(inputs) + "\n").encode("utf-8")
    expected = oracle_output(input_data).decode("utf-8").splitlines()

    # The replacement is executed as the unprivileged agent user while the legacy
    # executable is inaccessible, so a direct /app/loc_masker proxy cannot pass.
    with oracle_blocked_for_agent():
        agent_proc = run_as_agent_user(["python3", AGENT_SCRIPT], input_data=input_data, timeout=60)

    assert agent_proc.returncode == 0, (
        f"Agent script failed: {agent_proc.stderr.decode('utf-8', errors='replace')}"
    )
    agent_output = agent_proc.stdout.decode("utf-8").splitlines()

    assert len(expected) == len(agent_output), "Agent output line count differs from oracle."
    for i, (oracle_line, agent_line) in enumerate(zip(expected, agent_output)):
        if oracle_line != agent_line:
            pytest.fail(
                f"Mismatch on line {i + 1}.\n"
                f"Input:\n{inputs[i]}\n"
                f"Oracle output:\n{oracle_line}\n"
                f"Agent output:\n{agent_line}\n"
            )


def test_parallel_process_executes_and_merges_output():
    random.seed(314159)
    records = [json.dumps(generate_input_json()) for _ in range(513)]
    input_data = ("\n".join(records) + "\n").encode("utf-8")
    expected = oracle_output(input_data)

    fd, input_path = tempfile.mkstemp(prefix="loc-events-", suffix=".jsonl", dir="/tmp")
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(input_data)
        os.chmod(input_path, 0o644)

        with oracle_blocked_for_agent():
            proc = run_as_agent_user(
                ["bash", PARALLEL_SCRIPT, input_path],
                timeout=60,
            )

        assert proc.returncode == 0, (
            f"Parallel script failed: {proc.stderr.decode('utf-8', errors='replace')}"
        )
        assert proc.stdout == expected, (
            "parallel_process.sh did not produce the byte-for-byte merged oracle output"
        )
    finally:
        if os.path.exists(input_path):
            os.unlink(input_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
