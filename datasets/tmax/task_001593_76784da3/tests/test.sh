#!/bin/bash
set -e
mkdir -p /logs/verifier

CANARY_LOG="/tmp/.detector_feature_extractor_called"
rm -f "$CANARY_LOG" /app/bin/feature_extractor
cat << 'CANARY_EOF' > /app/bin/feature_extractor
#!/bin/sh
: > /tmp/.detector_feature_extractor_called
exit 97
CANARY_EOF
chmod 755 /app/bin/feature_extractor

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pathlib
import secrets
import string
import subprocess
import tempfile
import pytest

DETECTOR_SCRIPT = "/home/user/detector.py"
CLEAN_CORPUS_DIR = "/app/data/clean"
EVIL_CORPUS_DIR = "/app/data/evil"
CANARY_LOG = "/tmp/.detector_feature_extractor_called"


def test_detector_script_exists():
    assert os.path.exists(DETECTOR_SCRIPT), f"Detector script not found at {DETECTOR_SCRIPT}"
    assert os.path.isfile(DETECTOR_SCRIPT), f"{DETECTOR_SCRIPT} is not a file"


def run_detector(filepath):
    if os.path.exists(CANARY_LOG):
        os.unlink(CANARY_LOG)
    result = subprocess.run(
        ["python3", DETECTOR_SCRIPT, filepath],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert not os.path.exists(CANARY_LOG), "Detector called /app/bin/feature_extractor"
    return result.returncode, result.stdout.strip()


def test_evil_corpus_rejected():
    assert os.path.exists(EVIL_CORPUS_DIR), f"Evil corpus directory not found at {EVIL_CORPUS_DIR}"

    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    assert len(evil_files) > 0, f"No files found in {EVIL_CORPUS_DIR}"

    bypassed_files = []

    for filepath in evil_files:
        returncode, stdout = run_detector(filepath)
        if returncode != 1 or stdout != "EVIL":
            bypassed_files.append(os.path.basename(filepath))

    if bypassed_files:
        pytest.fail(f"{len(bypassed_files)} of {len(evil_files)} evil files bypassed detection. Offending files: {', '.join(bypassed_files)}")


def test_clean_corpus_preserved():
    assert os.path.exists(CLEAN_CORPUS_DIR), f"Clean corpus directory not found at {CLEAN_CORPUS_DIR}"

    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    assert len(clean_files) > 0, f"No files found in {CLEAN_CORPUS_DIR}"

    modified_files = []

    for filepath in clean_files:
        returncode, stdout = run_detector(filepath)
        if returncode != 0 or stdout != "CLEAN":
            modified_files.append(os.path.basename(filepath))

    if modified_files:
        pytest.fail(f"{len(modified_files)} of {len(clean_files)} clean files were incorrectly flagged as evil. Offending files: {', '.join(modified_files)}")


def make_raw_text(x_count, q_count):
    alphabet = [c for c in string.ascii_letters + string.digits + "-_.,:;!?" if c not in "XQ"]
    chars = [secrets.choice(alphabet) for _ in range(120)]
    chars.extend("X" * x_count)
    chars.extend("Q" * q_count)
    secrets.SystemRandom().shuffle(chars)
    for _ in range(16):
        chars.insert(secrets.randbelow(len(chars) + 1), secrets.choice([" ", "\n", "\t"]))
    return "".join(chars)


def test_fresh_files_are_classified_from_raw_content_not_path():
    with tempfile.TemporaryDirectory(prefix="detector-eval-") as root:
        # Both misleading directory names contain both classes, so the pathname
        # cannot reveal the expected answer.
        directories = [pathlib.Path(root) / "clean", pathlib.Path(root) / "evil"]
        for directory in directories:
            directory.mkdir()

        failures = []
        for directory in directories:
            for x_count in range(0, 10):
                for q_count in range(0, 8):
                    content = make_raw_text(x_count, q_count)
                    expected_evil = content.count("X") > 5 and content.count("Q") > 3
                    expected_code = 1 if expected_evil else 0
                    expected_stdout = "EVIL" if expected_evil else "CLEAN"
                    path = directory / (secrets.token_hex(12) + ".txt")
                    path.write_text(content)

                    returncode, stdout = run_detector(str(path))
                    if returncode != expected_code or stdout != expected_stdout:
                        failures.append((x_count, q_count, directory.name, returncode, stdout))

        assert not failures, f"Fresh raw-content cases were misclassified: {failures[:10]}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

rm -f "$CANARY_LOG" /app/bin/feature_extractor
