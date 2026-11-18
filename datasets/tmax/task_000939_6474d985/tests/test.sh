#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os


def test_proof_file_exists_and_correct():
    path = '/home/user/audit/proof.txt'
    assert os.path.isfile(path), f"The proof file {path} was not created. The exploit or subsequent execution failed."

    with open(path, 'r') as f:
        content = f.read().strip()

    assert content == "AUDIT_SUCCESS", f"The proof file contains '{content}' instead of the expected 'AUDIT_SUCCESS'."


def test_vuln_cron_overwritten_correctly():
    path = '/home/user/audit/vuln_cron.sh'
    assert os.path.isfile(path), f"The script {path} is missing."

    with open(path, 'r') as f:
        content = f.read().strip()

    expected_payload = 'echo "AUDIT_SUCCESS" > /home/user/audit/proof.txt'
    assert expected_payload in content, "The vuln_cron.sh script does not contain the expected payload. The path traversal overwrite may have failed."


def test_upload_handler_was_used():
    marker = '/var/lib/audit-task/upload_handler_used'
    assert os.path.isfile(marker), "No protected record shows that upload_handler.sh performed the target overwrite."
    st = os.stat(marker)
    assert st.st_uid == 0, "The protected upload record is not root-owned."
    with open(marker, 'r') as f:
        assert f.read().strip() == 'verified-target-overwrite'


def test_upload_handler_not_modified():
    handler = '/home/user/audit/upload_handler.sh'
    baseline = '/var/lib/audit-task/upload_handler.sha256'
    with open(handler, 'rb') as f:
        actual = hashlib.sha256(f.read()).hexdigest()
    with open(baseline, 'r') as f:
        expected = f.read().strip()
    assert actual == expected, "upload_handler.sh was modified."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
