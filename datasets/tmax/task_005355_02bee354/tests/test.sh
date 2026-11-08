#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import random
import string
import csv
from datetime import datetime


def test_subs_srt_exists():
    subs_path = "/home/user/subs.srt"
    assert os.path.isfile(subs_path), f"Subtitle file is missing at {subs_path}"
    with open(subs_path, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()
    assert "-->" in content, "The file does not appear to be a valid SRT file (missing '-->')."

    expected_path = "/tmp/expected_subs.srt"
    result = subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-i", "/app/presentation.mp4",
         "-map", "0:s:0", "-c:s", "srt", expected_path],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Failed to extract reference subtitle stream: {result.stderr}"

    with open(expected_path, 'r', encoding='utf-8-sig', errors='strict') as f:
        expected = f.read()

    def normalize_srt(text):
        return text.replace('\r\n', '\n').replace('\r', '\n').strip()

    assert normalize_srt(content) == normalize_srt(expected), (
        "/home/user/subs.srt does not match the primary subtitle stream extracted "
        "from /app/presentation.mp4."
    )


def test_hourly_counts_correct():
    csv_path = "/app/metadata.csv"
    output_path = "/home/user/hourly_counts.txt"

    assert os.path.isfile(output_path), f"Output file missing at {output_path}"

    counts = {}
    if os.path.isfile(csv_path):
        with open(csv_path, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row in reader:
                ts_str = row.get('timestamp', '')
                try:
                    dt = datetime.fromisoformat(ts_str.replace('Z', '+00:00'))
                    hour_str = dt.strftime("%Y-%m-%d %H:00")
                    counts[hour_str] = counts.get(hour_str, 0) + 1
                except ValueError:
                    continue

    expected_lines = [f"{k},{v}" for k, v in sorted(counts.items())]

    with open(output_path, 'r', encoding='utf-8') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, "The hourly counts in /home/user/hourly_counts.txt do not match the expected aggregation."


def test_cron_job_and_cleanup_script():
    script_path = "/home/user/cleanup.sh"
    assert os.path.isfile(script_path), f"Cleanup script missing at {script_path}"
    assert os.access(script_path, os.X_OK), f"Cleanup script is not executable: {script_path}"

    with open(script_path, 'r', encoding='utf-8') as f:
        cleanup_lines = f.read().splitlines()
    assert cleanup_lines == ["#!/bin/bash", 'echo "cleaned"'], (
        'Cleanup script must contain only #!/bin/bash and echo "cleaned".'
    )

    cleanup_result = subprocess.run([script_path], capture_output=True, text=True)
    assert cleanup_result.returncode == 0, f"Cleanup script failed: {cleanup_result.stderr}"
    assert cleanup_result.stdout == "cleaned\n", "Cleanup script must output exactly 'cleaned'."
    assert cleanup_result.stderr == "", "Cleanup script produced unexpected stderr."

    result = subprocess.run(['crontab', '-l'], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to read crontab."

    cron_lines = result.stdout.strip().split('\n')
    expected_cron = "30 2 * * * /home/user/cleanup.sh"

    normalized_expected = expected_cron.split()
    found = False
    for line in cron_lines:
        if line.startswith('#'):
            continue
        if line.split() == normalized_expected:
            found = True
            break

    assert found, f"Cron job not found or incorrect. Expected: '{expected_cron}'"


def test_metric_sh_fuzz():
    agent_script = "/home/user/metric.sh"
    assert os.path.isfile(agent_script), f"Agent script missing at {agent_script}"
    assert os.access(agent_script, os.X_OK), f"Agent script is not executable: {agent_script}"

    oracle_script = "/tmp/oracle_metric.sh"
    oracle_code = """#!/bin/bash
str1=$(echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/ /g')
str2=$(echo "$2" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/ /g')

# extract unique non-empty words
set1=$(echo "$str1" | tr ' ' '\n' | grep -v '^$' | sort -u)
set2=$(echo "$str2" | tr ' ' '\n' | grep -v '^$' | sort -u)

if [ -z "$set1" ] && [ -z "$set2" ]; then
    echo 1000
    exit 0
fi

union=$(echo -e "${set1}\\n${set2}" | grep -v '^$' | sort -u | wc -l)
intersection=$(echo -e "${set1}\\n${set2}" | grep -v '^$' | sort | uniq -d | wc -l)

echo $(( (intersection * 1000) / union ))
"""
    with open(oracle_script, 'w') as f:
        f.write(oracle_code)
    os.chmod(oracle_script, 0o755)

    random.seed(42)
    chars = string.ascii_letters + string.digits + " ,.-;'\""

    def generate_random_string():
        length = random.randint(0, 100)
        return ''.join(random.choice(chars) for _ in range(length))

    test_cases = [
        ("", ""),
        (" ,.-; ", " ,.-; "),
        ("hello world", "world hello"),
        ("a b c", "c d e"),
        ("123 abc", "abc 123"),
    ]

    for _ in range(195):
        test_cases.append((generate_random_string(), generate_random_string()))

    for str1, str2 in test_cases:
        agent_res = subprocess.run([agent_script, str1, str2], capture_output=True, text=True)
        oracle_res = subprocess.run([oracle_script, str1, str2], capture_output=True, text=True)

        agent_out = agent_res.stdout.strip()
        oracle_out = oracle_res.stdout.strip()

        assert agent_res.returncode == 0, f"Agent script failed on inputs: '{str1}', '{str2}'\nStderr: {agent_res.stderr}"
        assert agent_out == oracle_out, f"Mismatch on inputs:\nstr1: '{str1}'\nstr2: '{str2}'\nExpected: {oracle_out}\nGot: {agent_out}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
