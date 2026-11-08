#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import glob
import os
import re
import stat
import zipfile

TOKEN_RE = re.compile(r'SEC-ROT-[A-Z0-9]{16}')
REDACTION = '[REDACTED]'


def get_redacted_indices(text):
    return set(m.start() for m in re.finditer(r'\[REDACTED\]', text))


def evaluate(pred_path, truth_path):
    with open(pred_path, 'r', encoding='utf-8') as f:
        pred = f.read()
    with open(truth_path, 'r', encoding='utf-8') as f:
        truth = f.read()

    pred_idx = get_redacted_indices(pred)
    truth_idx = get_redacted_indices(truth)

    tp = len(pred_idx.intersection(truth_idx))
    fp = len(pred_idx - truth_idx)
    fn = len(truth_idx - pred_idx)

    precision = tp / (tp + fp) if (tp + fp) > 0 else 0
    recall = tp / (tp + fn) if (tp + fn) > 0 else 0
    f1 = 2 * (precision * recall) / (precision + recall) if (precision + recall) > 0 else 0
    return f1


def assert_only_tokens_redacted(source, pred):
    source_pos = 0
    pred_pos = 0

    while source_pos < len(source):
        token_match = TOKEN_RE.match(source, source_pos)
        if token_match and pred.startswith(REDACTION, pred_pos):
            source_pos = token_match.end()
            pred_pos += len(REDACTION)
            continue

        assert pred_pos < len(pred), 'Redacted log is truncated'
        assert source[source_pos] == pred[pred_pos], (
            f'Non-token log text was changed near source offset {source_pos}'
        )
        source_pos += 1
        pred_pos += 1

    assert pred_pos == len(pred), 'Redacted log contains added text'


def test_redacted_logs_exist_and_permissions():
    pred_path = "/home/user/redacted_logs.txt"
    assert os.path.exists(pred_path), f"File not found: {pred_path}"

    st = os.stat(pred_path)
    perms = stat.S_IMODE(st.st_mode)
    assert perms == 0o600, f"Expected permissions 0o600 for {pred_path}, but got {oct(perms)}"


def test_python_scripts_permissions():
    scripts = glob.glob("/home/user/*.py")
    scripts = [s for s in scripts if os.path.basename(s) != "test_final_state.py"]
    assert scripts, "No Python parser script found in /home/user"

    for script in scripts:
        assert os.path.isfile(script), f"Python script is not a file: {script}"
        st = os.stat(script)
        perms = stat.S_IMODE(st.st_mode)
        assert perms == 0o600, f"Expected permissions 0o600 for script {script}, but got {oct(perms)}"


def test_non_token_log_text_is_unchanged():
    pred_path = "/home/user/redacted_logs.txt"
    archive_path = "/app/evidence.zip"

    assert os.path.exists(pred_path), f"Prediction file not found: {pred_path}"
    assert os.path.exists(archive_path), f"Evidence archive not found: {archive_path}"

    with zipfile.ZipFile(archive_path) as archive:
        source = archive.read(
            "process_logs.txt", pwd=b"flamingo orange telescope"
        ).decode("utf-8")
    with open(pred_path, "r", encoding="utf-8") as f:
        pred = f.read()

    assert_only_tokens_redacted(source, pred)


def test_f1_score():
    pred_path = "/home/user/redacted_logs.txt"
    truth_path = "/app/truth_redacted_logs.txt"

    assert os.path.exists(pred_path), f"Prediction file not found: {pred_path}"
    assert os.path.exists(truth_path), f"Truth file not found: {truth_path}"

    f1 = evaluate(pred_path, truth_path)
    assert f1 >= 0.99, f"F1 score {f1:.4f} is below the threshold of 0.99"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
