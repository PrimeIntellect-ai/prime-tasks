#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import subprocess
import tempfile

import pytest

SCRIPT_PATH = "/home/user/detector.py"


def run_detector(corpus_dir):
    assert os.path.isfile(SCRIPT_PATH), f"Detector script not found at {SCRIPT_PATH}"

    result = subprocess.run(
        ["python3", SCRIPT_PATH, corpus_dir],
        capture_output=True,
        text=True,
        timeout=20,
    )

    assert result.returncode == 0, (
        f"Detector script failed with return code {result.returncode}.\n"
        f"Stderr: {result.stderr}"
    )

    try:
        output_json = json.loads(result.stdout)
    except json.JSONDecodeError:
        pytest.fail(f"Detector script did not output valid JSON.\nStdout: {result.stdout}")

    assert isinstance(output_json, dict), "Detector output must be a JSON dictionary"
    return output_json


def write_corpus(parent, records):
    corpus_dir = tempfile.mkdtemp(prefix=f"corpus_{secrets.token_hex(8)}_", dir=parent)
    expected = {}
    for contents, classification in records:
        filename = f"audit_{secrets.token_hex(10)}.txt"
        with open(os.path.join(corpus_dir, filename), "w", encoding="utf-8") as handle:
            handle.write(contents)
        expected[filename] = classification
    return corpus_dir, expected


def assert_classifications(corpus_dir, expected):
    assert os.path.isdir(corpus_dir), f"Corpus directory is missing at {corpus_dir}"
    expected_files = set(os.listdir(corpus_dir))
    assert expected_files == set(expected)

    output_json = run_detector(corpus_dir)
    failures = []
    for filename in expected_files:
        if filename not in output_json:
            failures.append(f"{filename} (missing from output)")
        elif not isinstance(output_json[filename], bool):
            failures.append(f"{filename} (value is not a JSON boolean)")
        elif output_json[filename] is not expected[filename]:
            failures.append(
                f"{filename} (flagged {output_json[filename]}, expected {expected[filename]})"
            )

    if failures:
        pytest.fail(
            f"{len(failures)} of {len(expected_files)} files were misclassified:\n"
            + "\n".join(failures)
        )


def test_detector_on_unseen_corpora():
    root = tempfile.mkdtemp(prefix=f"verification_{secrets.token_hex(12)}_")

    password = secrets.token_urlsafe(18)
    aws_secret = secrets.token_urlsafe(30)
    api_token = secrets.token_hex(24)
    bearer = secrets.token_urlsafe(28)

    violating_records = [
        (f"cmdline: python3 backup.py --password={password}\nenviron: PATH=/usr/bin\n", True),
        (f"cmdline: aws s3 cp archive s3://bucket --aws-secret-access-key {aws_secret}\nenviron: HOME=/srv\n", True),
        (f"cmdline: node sync.js --api-token={api_token}\nenviron: NODE_ENV=production\n", True),
        (f"cmdline: curl -H Authorization: Bearer {bearer} https://service.local/api\nenviron: PATH=/usr/bin\n", True),
    ]

    benign_records = [
        ("cmdline: /usr/sbin/cron -f\nenviron: PATH=/usr/sbin:/usr/bin\n", False),
        (f"cmdline: python3 backup.py\nenviron: DB_PASSWORD={password}\n", False),
        (f"cmdline: aws-agent --config /etc/aws-agent.conf\nenviron: AWS_SECRET_ACCESS_KEY={aws_secret}\n", False),
        (f"cmdline: node service.js\nenviron: API_TOKEN={api_token}\n", False),
        ("cmdline: python3 worker.py --credentials-file /run/secrets/application\nenviron: PATH=/usr/bin\n", False),
    ]

    corpora = [
        write_corpus(root, violating_records),
        write_corpus(root, benign_records),
    ]
    random.SystemRandom().shuffle(corpora)

    for corpus_dir, expected in corpora:
        assert_classifications(corpus_dir, expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
