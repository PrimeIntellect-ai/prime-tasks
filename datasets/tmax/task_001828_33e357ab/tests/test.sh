#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shlex
import stat
import string
import subprocess
import uuid
from pathlib import Path

import pytest

PACKAGE = Path("/app/bayes_text_filter-1.2.0")
BINARY_PATH = PACKAGE / "bayes_filter"
WRAPPER_PATH = PACKAGE / "bayes_score.sh"
EVIL_CORPUS_PATH = Path("/app/data/corpus/evil")
CLEAN_CORPUS_PATH = Path("/app/data/corpus/clean")
SCRIPT_PATH = Path("/home/user/clean_dataset.sh")
LOG_PATH = Path("/home/user/cleaning.log")
KEYWORDS = ("viagra", "hack", "crypto", "drop")


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=20, **kwargs)


def tokenize(text):
    return text.lower().translate(str.maketrans("", "", string.punctuation))


def expected_score(text):
    score = 0
    for word in tokenize(text).split():
        if any(keyword in word for keyword in KEYWORDS):
            score += 20
    return score


def test_script_exists_and_executable():
    assert SCRIPT_PATH.is_file(), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_bayes_filter_compiled():
    assert BINARY_PATH.is_file(), f"Binary {BINARY_PATH} was not compiled. Did you fix the Makefile and run make?"
    assert os.access(BINARY_PATH, os.X_OK), f"Binary {BINARY_PATH} is not executable."


def test_makefile_builds_successfully():
    clean = run(["make", "clean"], cwd=PACKAGE)
    assert clean.returncode == 0, f"make clean failed:\n{clean.stdout}\n{clean.stderr}"
    build = run(["make"], cwd=PACKAGE)
    assert build.returncode == 0, f"make failed:\n{build.stdout}\n{build.stderr}"
    assert BINARY_PATH.is_file() and os.access(BINARY_PATH, os.X_OK)


def test_wrapper_executes_classifier_and_prints_numeric_score(tmp_path):
    assert WRAPPER_PATH.is_file(), "bayes_score.sh is missing"
    assert os.access(WRAPPER_PATH, os.X_OK), "bayes_score.sh is not executable"

    spaced_dir = tmp_path / "directory with spaces"
    spaced_dir.mkdir()
    sample = spaced_dir / f"sample-{uuid.uuid4().hex}.txt"
    sample.write_text("viagra hack harmless crypto drop\n")

    result = run([str(WRAPPER_PATH), str(sample)], cwd=tmp_path)
    assert result.returncode == 0, f"Wrapper failed: {result.stderr}"
    assert re.fullmatch(r"\d+", result.stdout.strip()), f"Wrapper output is not numeric: {result.stdout!r}"
    assert int(result.stdout.strip()) == 80


def test_clean_corpus_preserved(tmp_path):
    out_dir = tmp_path / "out_clean"
    out_dir.mkdir()
    result = run([str(SCRIPT_PATH), str(CLEAN_CORPUS_PATH), str(out_dir)])
    assert result.returncode == 0, f"Script failed on clean corpus with error: {result.stderr}"

    clean_files = [p for p in CLEAN_CORPUS_PATH.iterdir() if p.name.endswith(".txt")]
    missing_files = []
    modified_files = []
    for src in clean_files:
        dst = out_dir / src.name
        if not dst.is_file():
            missing_files.append(src.name)
        elif src.read_bytes() != dst.read_bytes():
            modified_files.append(src.name)

    failed_clean = len(missing_files) + len(modified_files)
    error_msg = f"{failed_clean} of {len(clean_files)} clean modified/rejected."
    if missing_files:
        error_msg += f"\nMissing files: {missing_files[:5]}"
    if modified_files:
        error_msg += f"\nModified files: {modified_files[:5]}"
    assert failed_clean == 0, error_msg


def test_evil_corpus_obeys_score_threshold(tmp_path):
    out_dir = tmp_path / "out_evil"
    out_dir.mkdir()
    result = run([str(SCRIPT_PATH), str(EVIL_CORPUS_PATH), str(out_dir)])
    assert result.returncode == 0, f"Script failed on evil corpus with error: {result.stderr}"

    for src in EVIL_CORPUS_PATH.iterdir():
        if not src.name.endswith(".txt"):
            continue
        score = expected_score(src.read_text())
        dst = out_dir / src.name
        if score > 50:
            assert not dst.exists(), f"{src.name} scored {score} and should have been dropped"
        else:
            assert dst.is_file(), f"{src.name} scored {score} and should have been kept"
            assert dst.read_bytes() == src.read_bytes(), f"Kept file {src.name} was modified"


def test_dynamic_cleaning_tokenization_wrapper_use_logging_and_threshold(tmp_path):
    input_dir = tmp_path / f"input-{uuid.uuid4().hex}"
    output_dir = tmp_path / f"output-{uuid.uuid4().hex}"
    capture_dir = tmp_path / f"captures-{uuid.uuid4().hex}"
    input_dir.mkdir()
    output_dir.mkdir()
    capture_dir.mkdir()

    cases = {
        f"plain-{uuid.uuid4().hex}.txt": "Ordinary, friendly text with no suspicious terms.\n",
        f"threshold-{uuid.uuid4().hex}.txt": "Please DROP this harmless note about CRYPTO.\n",
        f"anomaly-{uuid.uuid4().hex}.txt": "VIAGRA!!! then HaCk??? and finally CRYPTO,,,\n",
    }
    ignored_name = f"ignored-{uuid.uuid4().hex}.md"
    for name, content in cases.items():
        (input_dir / name).write_text(content)
    (input_dir / ignored_name).write_text("viagra hack crypto drop")

    old_log = LOG_PATH.read_text() if LOG_PATH.exists() else ""

    backup = PACKAGE / f".bayes_score.backup-{uuid.uuid4().hex}"
    os.replace(WRAPPER_PATH, backup)
    marker = shlex.quote(str(capture_dir))
    spy = f'''#!/bin/bash
set -e
capture_dir={marker}
i=0
while [ -e "$capture_dir/capture_$i" ]; do i=$((i+1)); done
cp -- "$1" "$capture_dir/capture_$i"
exec /app/bayes_text_filter-1.2.0/bayes_filter "$1"
'''
    try:
        WRAPPER_PATH.write_text(spy)
        WRAPPER_PATH.chmod(0o755)
        result = run([str(SCRIPT_PATH), str(input_dir), str(output_dir)])
    finally:
        try:
            WRAPPER_PATH.unlink()
        except FileNotFoundError:
            pass
        os.replace(backup, WRAPPER_PATH)

    assert result.returncode == 0, f"Cleaner failed: {result.stderr}"

    expected_entries = []
    expected_token_lists = []
    for name, content in cases.items():
        score = expected_score(content)
        kept = score <= 50
        dst = output_dir / name
        if kept:
            assert dst.is_file(), f"{name} scored {score} but was not kept"
            assert dst.read_bytes() == (input_dir / name).read_bytes(), f"{name} was modified"
        else:
            assert not dst.exists(), f"{name} scored {score} but was not dropped"
        expected_entries.append(f"[{'KEEP' if kept else 'DROP'}] {name} {score}")
        expected_token_lists.append(tokenize(content).split())

    assert not (output_dir / ignored_name).exists(), "Non-.txt file was processed"

    captures = sorted(capture_dir.glob("capture_*"))
    assert len(captures) == len(cases), "Cleaner did not call bayes_score.sh exactly once per .txt file"
    actual_token_lists = []
    for captured in captures:
        text = captured.read_text()
        assert text == text.lower(), "Text passed to the wrapper was not lowercased"
        assert not any(ch in string.punctuation for ch in text), "Punctuation was not removed before scoring"
        actual_token_lists.append(text.split())
    assert sorted(actual_token_lists) == sorted(expected_token_lists), "Wrapper did not receive the tokenized documents"

    assert LOG_PATH.exists(), "cleaning.log was not created"
    new_log = LOG_PATH.read_text()
    assert new_log.startswith(old_log), "Cleaner overwrote existing log entries instead of appending"
    appended = new_log[len(old_log):].splitlines()
    assert sorted(appended) == sorted(expected_entries), f"Incorrect appended log entries: {appended}"
    assert all(ignored_name not in line for line in appended), "Non-.txt file was logged as processed"


def test_requires_exactly_two_arguments(tmp_path):
    input_dir = tmp_path / "input"
    output_dir = tmp_path / "output"
    input_dir.mkdir()
    output_dir.mkdir()

    for args in ([], [str(input_dir)], [str(input_dir), str(output_dir), "extra"]):
        result = run([str(SCRIPT_PATH), *args])
        assert result.returncode != 0, f"Cleaner accepted invalid argument list: {args}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
