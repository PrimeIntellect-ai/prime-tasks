#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import pwd
import random
import shutil
import string
import subprocess
from collections import Counter
from datetime import datetime, timedelta

import pytest


def test_process_script_exists_and_executable():
    script_path = '/home/user/process.sh'
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"The script {script_path} is not executable."

    with open(script_path, 'rb') as f:
        first_line = f.readline().rstrip(b'\r\n')
    assert first_line == b'#!/bin/bash', "The processing script must use #!/bin/bash."


def test_summary_report_content():
    report_path = '/home/user/reports/summary.txt'
    assert os.path.isfile(report_path), f"The report {report_path} does not exist."

    with open(report_path, 'r') as f:
        content = f.read().strip()

    expected_content = """Daily Feedback Report
Most frequent words:
1. quality (5)
2. product (4)
3. fantastic (3)"""

    assert content == expected_content, f"The content of {report_path} does not match the expected output."


def test_pipeline_log_format():
    log_path = '/home/user/logs/pipeline.log'
    assert os.path.isfile(log_path), f"The log file {log_path} does not exist."

    with open(log_path, 'r') as f:
        lines = f.readlines()

    assert len(lines) > 0, f"The log file {log_path} is empty."

    last_line = lines[-1].strip()
    pattern = r"^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] Pipeline completed successfully\.$"
    assert re.match(pattern, last_line), f"The log entry format is incorrect: {last_line}"


def test_crontab_entry():
    try:
        result = subprocess.run(['crontab', '-l', '-u', 'user'], capture_output=True, text=True, check=True)
        crontab_content = result.stdout
    except subprocess.CalledProcessError:
        pytest.fail("Failed to retrieve crontab for 'user'.")

    pattern = r"^0\s+2\s+\*\s+\*\s+\*\s+/home/user/process\.sh"
    match_found = any(re.match(pattern, line.strip()) for line in crontab_content.splitlines())
    assert match_found, "The crontab for 'user' does not contain the correct schedule for /home/user/process.sh."


def test_script_processes_changed_input_and_appends_current_log_entry():
    user = pwd.getpwnam('user')
    uid, gid = user.pw_uid, user.pw_gid

    rng = random.SystemRandom()
    words = set()
    while len(words) < 4:
        words.add(''.join(rng.choice(string.ascii_lowercase) for _ in range(8)))
    word1, word2, word3, word4 = sorted(words)

    csv_content = (
        "id|username|feedback_text\n"
        f"1|alice|{word1.upper()}!!! {word2}, {word3} and it\n"
        f"2|bob|{word1} {word1.upper()} {word2}; {word4}\n"
        f"3|cara|{word1}-{word2} {word3.upper()} {word4}\n"
        f"4|dave|{word1} {word2} {word3} {word4}\n"
    )

    marker = ''.join(rng.choice(string.ascii_letters) for _ in range(16))
    template_content = (
        f"Dynamic report {marker}\n"
        "Third={{WORD3}}/{{COUNT3}}\n"
        "First={{WORD1}}/{{COUNT1}}\n"
        "Second={{WORD2}}/{{COUNT2}}\n"
    )

    # Independently derive the expected ranking from the generated CSV.
    tokens = []
    for line in csv_content.splitlines()[1:]:
        feedback = line.split('|', 2)[2].lower()
        tokens.extend(w for w in re.sub(r'[^a-z]', ' ', feedback).split() if len(w) >= 4)
    ranking = sorted(Counter(tokens).items(), key=lambda item: (-item[1], item[0]))[:3]
    assert ranking == [(word1, 5), (word2, 4), (word3, 3)]

    expected_report = template_content
    for rank, (word, count) in enumerate(ranking, start=1):
        expected_report = expected_report.replace('{{WORD%d}}' % rank, word)
        expected_report = expected_report.replace('{{COUNT%d}}' % rank, str(count))

    os.makedirs('/home/user/data', exist_ok=True)
    with open('/home/user/data/feedback.csv', 'w') as f:
        f.write(csv_content)
    with open('/home/user/template.txt', 'w') as f:
        f.write(template_content)

    # The script must create a missing report directory.
    shutil.rmtree('/home/user/reports', ignore_errors=True)

    os.makedirs('/home/user/logs', exist_ok=True)
    sentinel = f"preexisting-log-{marker}\n"
    with open('/home/user/logs/pipeline.log', 'w') as f:
        f.write(sentinel)

    os.chown('/home/user', uid, gid)
    os.chmod('/home/user', 0o755)
    for path in ['/home/user/data', '/home/user/data/feedback.csv', '/home/user/template.txt',
                 '/home/user/logs', '/home/user/logs/pipeline.log']:
        os.chown(path, uid, gid)
    os.chmod('/home/user/data', 0o755)
    os.chmod('/home/user/logs', 0o755)
    os.chmod('/home/user/data/feedback.csv', 0o644)
    os.chmod('/home/user/template.txt', 0o644)
    os.chmod('/home/user/logs/pipeline.log', 0o644)

    started = datetime.now()
    result = subprocess.run(
        ['runuser', '-u', 'user', '--', '/home/user/process.sh'],
        capture_output=True,
        text=True,
        timeout=30,
    )
    finished = datetime.now()
    assert result.returncode == 0, (
        f"process.sh failed on changed input with exit code {result.returncode}: "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )

    report_path = '/home/user/reports/summary.txt'
    assert os.path.isfile(report_path), "process.sh did not create the report for changed input."
    with open(report_path, 'r') as f:
        actual_report = f.read()
    assert actual_report.strip() == expected_report.strip(), (
        "process.sh did not normalize, count, rank, or substitute the changed input correctly."
    )

    with open('/home/user/logs/pipeline.log', 'r') as f:
        log_content = f.read()
    assert log_content.startswith(sentinel), "process.sh replaced the log instead of appending to it."
    appended = log_content[len(sentinel):]
    match = re.fullmatch(
        r"\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] Pipeline completed successfully\.\n?",
        appended,
    )
    assert match, "Each execution must append one correctly formatted success log entry."
    timestamp = datetime.strptime(match.group(1), '%Y-%m-%d %H:%M:%S')
    assert started - timedelta(seconds=1) <= timestamp <= finished + timedelta(seconds=1), (
        "The appended log timestamp is not the current system time."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
