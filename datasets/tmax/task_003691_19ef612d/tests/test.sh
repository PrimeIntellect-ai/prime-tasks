#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import stat
import subprocess
import tempfile
import uuid
import pytest

CLASSIFIER_SCRIPT = "/home/user/classifier.sh"
EXTRACTOR_DIR = "/app/extractor_src"
EXTRACTOR = os.path.join(EXTRACTOR_DIR, "bin_extractor")
EVIL_CORPUS_DIR = "/app/corpora/evil/"
CLEAN_CORPUS_DIR = "/app/corpora/clean/"
RANSOM_NOTE = "/app/ransom_note.png"


def run_classifier(path):
    return subprocess.run(
        ["bash", CLASSIFIER_SCRIPT, path],
        capture_output=True,
        timeout=10,
    )


def extract_magic_from_image():
    result = subprocess.run(
        ["tesseract", RANSOM_NOTE, "stdout"],
        text=True,
        capture_output=True,
        check=True,
        timeout=20,
    )
    matches = re.findall(r"(?i)(?<![0-9a-f])[0-9a-f]{16}(?![0-9a-f])", result.stdout)
    assert matches, f"Could not derive a 16-character hexadecimal signature from {RANSOM_NOTE}"
    return matches[0].upper()


def compile_binary(output_path, displayed_string):
    source_path = output_path + ".c"
    with open(source_path, "w") as f:
        f.write('#include <stdio.h>\n')
        f.write('int main(void) { puts("%s"); return 0; }\n' % displayed_string)
    subprocess.run(["gcc", source_path, "-o", output_path], check=True, timeout=20)
    os.unlink(source_path)


def test_classifier_script_exists():
    assert os.path.isfile(CLASSIFIER_SCRIPT), f"Classifier script is missing at {CLASSIFIER_SCRIPT}"
    assert os.access(CLASSIFIER_SCRIPT, os.X_OK) or os.access(CLASSIFIER_SCRIPT, os.R_OK), f"Classifier script at {CLASSIFIER_SCRIPT} is not readable/executable"


def test_extractor_source_builds_and_result_is_real_executable():
    subprocess.run(["make", "clean"], cwd=EXTRACTOR_DIR, check=True, capture_output=True, timeout=20)
    subprocess.run(["make"], cwd=EXTRACTOR_DIR, check=True, capture_output=True, timeout=20)

    assert os.path.isfile(EXTRACTOR), f"Expected built extractor at {EXTRACTOR}"
    mode = os.stat(EXTRACTOR).st_mode
    assert mode & stat.S_IXUSR, "bin_extractor is not executable"
    with open(EXTRACTOR, "rb") as f:
        assert f.read(4) == b"\x7fELF", "bin_extractor is not a compiled ELF executable"

    magic = extract_magic_from_image()
    with tempfile.TemporaryDirectory(prefix="extractor-check-") as tmp:
        sample = os.path.join(tmp, uuid.uuid4().hex)
        compile_binary(sample, "prefix-" + magic + "-suffix")
        result = subprocess.run([EXTRACTOR, sample], capture_output=True, timeout=10)
        assert result.returncode == 0, "bin_extractor failed on a valid ELF binary"
        assert magic.encode() in result.stdout, "bin_extractor did not extract the embedded magic string"


def test_evil_corpus_classification():
    if not os.path.isfile(CLASSIFIER_SCRIPT):
        pytest.fail(f"Classifier script missing at {CLASSIFIER_SCRIPT}")

    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    assert len(evil_files) > 0, f"No files found in evil corpus at {EVIL_CORPUS_DIR}"

    failed_files = []
    for filepath in evil_files:
        result = run_classifier(filepath)
        if result.returncode != 1:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil files bypassed the classifier (expected exit code 1). Offending files: {', '.join(failed_files)}")


def test_clean_corpus_classification():
    if not os.path.isfile(CLASSIFIER_SCRIPT):
        pytest.fail(f"Classifier script missing at {CLASSIFIER_SCRIPT}")

    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    assert len(clean_files) > 0, f"No files found in clean corpus at {CLEAN_CORPUS_DIR}"

    failed_files = []
    for filepath in clean_files:
        result = run_classifier(filepath)
        if result.returncode != 0:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean files were incorrectly flagged (expected exit code 0). Offending files: {', '.join(failed_files)}")


def test_randomized_path_independent_classification_uses_extractor():
    magic = extract_magic_from_image()
    decoy = "0123456789ABCDEF"
    if decoy == magic:
        decoy = "FEDCBA9876543210"

    with tempfile.TemporaryDirectory(prefix="neutral-corpus-") as tmp:
        # Both files have unpredictable, semantically neutral names in the same directory.
        malicious = os.path.join(tmp, uuid.uuid4().hex)
        clean = os.path.join(tmp, uuid.uuid4().hex)
        compile_binary(malicious, "data:" + magic + ":end")
        compile_binary(clean, "data:" + decoy + ":end")

        backup = os.path.join(tmp, "real_extractor")
        log_path = os.path.join(tmp, "extractor_calls")
        shutil.copy2(EXTRACTOR, backup)

        # Interpose a transparent logger so successful output alone is insufficient:
        # the classifier must actually invoke the built extractor for each input.
        wrapper = f'''#!/bin/bash
printf '%s\\0' "$@" >> {log_path!r}
exec {backup!r} "$@"
'''
        try:
            with open(EXTRACTOR, "w") as f:
                f.write(wrapper)
            os.chmod(EXTRACTOR, 0o755)

            evil_result = run_classifier(malicious)
            clean_result = run_classifier(clean)

            assert evil_result.returncode == 1, "Randomly located malicious binary was not detected"
            assert clean_result.returncode == 0, "Randomly located clean binary was incorrectly flagged"
            assert os.path.isfile(log_path), "classifier.sh never invoked bin_extractor"
            with open(log_path, "rb") as f:
                calls = [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
            assert malicious in calls, "classifier.sh did not pass the randomized malicious binary to bin_extractor"
            assert clean in calls, "classifier.sh did not pass the randomized clean binary to bin_extractor"
        finally:
            shutil.copy2(backup, EXTRACTOR)
            os.chmod(EXTRACTOR, 0o755)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
