#!/bin/bash
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import stat
import subprocess

import numpy as np
import pytest

OUTPUT_PATH = "/home/user/output/analysis.json"
AUDIO_PATH = "/app/data/field_recording.wav"
PIPELINE_PATH = "/home/user/pipeline/process_audio.py"
CRON_SETUP_PATH = "/home/user/setup_cron.sh"


def assert_regular_file(path):
    assert os.path.exists(path), f"Required file is missing: {path}"
    assert stat.S_ISREG(os.stat(path, follow_symlinks=False).st_mode), f"Required path is not a regular file: {path}"


def test_pipeline_executes_and_creates_output():
    """Execute the submitted pipeline rather than trusting a pre-created JSON file."""
    assert_regular_file(PIPELINE_PATH)
    assert os.path.isfile(AUDIO_PATH), f"Audio file is missing: {AUDIO_PATH}"

    if os.path.lexists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    result = subprocess.run(
        ["python3", PIPELINE_PATH],
        cwd="/home/user/pipeline",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, (
        f"process_audio.py failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT_PATH), "The pipeline did not create analysis.json."


def test_analysis_json_exists_and_structure():
    """Verify that the output JSON exists and has the correct structure."""
    assert os.path.isfile(OUTPUT_PATH), f"Output JSON is missing: {OUTPUT_PATH}"

    with open(OUTPUT_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Output file is not valid JSON.")

    assert "transcription" in data, "Missing 'transcription' key in JSON."
    assert "mfcc_mean" in data, "Missing 'mfcc_mean' key in JSON."
    assert "mfcc_var" in data, "Missing 'mfcc_var' key in JSON."

    assert isinstance(data["transcription"], str), "'transcription' must be a string."
    assert isinstance(data["mfcc_mean"], list), "'mfcc_mean' must be a list."
    assert isinstance(data["mfcc_var"], list), "'mfcc_var' must be a list."

    assert len(data["mfcc_mean"]) == 13, f"Expected 13 MFCC means, got {len(data['mfcc_mean'])}."
    assert len(data["mfcc_var"]) == 13, f"Expected 13 MFCC variances, got {len(data['mfcc_var'])}."

    try:
        means = np.asarray(data["mfcc_mean"], dtype=float)
        variances = np.asarray(data["mfcc_var"], dtype=float)
    except (TypeError, ValueError):
        pytest.fail("MFCC means and variances must contain numeric values.")
    assert np.all(np.isfinite(means)), "MFCC means must all be finite."
    assert np.all(np.isfinite(variances)), "MFCC variances must all be finite."
    assert np.all(variances >= 0), "MFCC variances cannot be negative."


def test_transcription_matches_recording():
    """Ensure the transcription contains recognizable words from the supplied speech."""
    with open(OUTPUT_PATH, "r") as f:
        transcription = json.load(f)["transcription"]

    words = set(re.findall(r"[a-z]+", transcription.lower()))
    expected_keywords = {
        "quick", "brown", "fox", "jumps", "lazy", "dog",
        "system", "monitors", "acoustic", "levels",
    }
    matched = words & expected_keywords
    assert len(matched) >= 4, (
        "Transcription does not sufficiently match the spoken recording; "
        f"recognized expected keywords: {sorted(matched)}"
    )


def test_cron_job_setup():
    """Execute the cron installer and verify a real 15-minute logged job is installed."""
    assert_regular_file(CRON_SETUP_PATH)
    subprocess.run(["crontab", "-r"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    result = subprocess.run(
        ["bash", CRON_SETUP_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"setup_cron.sh failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    try:
        crontab_output = subprocess.check_output(
            ["crontab", "-l"], stderr=subprocess.STDOUT
        ).decode("utf-8")
    except subprocess.CalledProcessError:
        pytest.fail("No crontab found for the current user.")

    # Preserve the original checks.
    valid_cron_time = ("*/15" in crontab_output or "0,15,30,45" in crontab_output or "15" in crontab_output)
    has_script = "process_audio.py" in crontab_output
    assert valid_cron_time and has_script, f"Cron job not properly set up. Current crontab:\n{crontab_output}"

    active_lines = [line.strip() for line in crontab_output.splitlines() if line.strip() and not line.lstrip().startswith("#")]
    valid_lines = []
    for line in active_lines:
        fields = line.split(None, 5)
        if len(fields) != 6:
            continue
        minute, hour, dom, month, dow, command = fields
        schedule_ok = minute in ("*/15", "0,15,30,45") and (hour, dom, month, dow) == ("*", "*", "*", "*")
        command_ok = re.search(r"(?:^|\s)(?:python3?\s+)?/home/user/pipeline/process_audio\.py(?:\s|$)", command)
        logging_ok = re.search(r"(?:>>?|&>)\s*/home/user/output/pipeline\.log(?:\s|$)", command)
        if schedule_ok and command_ok and logging_ok:
            valid_lines.append(line)
    assert valid_lines, f"No exact 15-minute pipeline job with pipeline.log redirection was found:\n{crontab_output}"


def test_mfcc_mse():
    """Compare submitted MFCC means and variances with values derived from the audio."""
    assert os.path.isfile(OUTPUT_PATH), f"Output JSON is missing: {OUTPUT_PATH}"
    assert os.path.isfile(AUDIO_PATH), f"Audio file is missing: {AUDIO_PATH}"

    with open(OUTPUT_PATH, "r") as f:
        data = json.load(f)

    agent_mfcc_mean = np.asarray(data["mfcc_mean"], dtype=float)
    agent_mfcc_var = np.asarray(data["mfcc_var"], dtype=float)

    import librosa
    y, sr = librosa.load(AUDIO_PATH, sr=16000)
    mfccs = librosa.feature.mfcc(y=y, sr=sr, n_mfcc=13, hop_length=160, n_fft=400)
    ref_mfcc_mean = np.mean(mfccs, axis=1)
    ref_mfcc_var = np.var(mfccs, axis=1)

    mse = np.mean((agent_mfcc_mean - ref_mfcc_mean) ** 2)
    threshold = 1.5
    assert mse <= threshold, f"MFCC mean MSE is {mse:.4f}, which exceeds the threshold of {threshold}."

    normalized_var_mse = np.mean(((agent_mfcc_var - ref_mfcc_var) / (np.abs(ref_mfcc_var) + 1.0)) ** 2)
    assert normalized_var_mse <= 0.01, (
        f"MFCC variance normalized MSE is {normalized_var_mse:.6f}, which exceeds 0.01."
    )
TEST_EOF

if python3 -m pip install --quiet --disable-pip-version-check 'librosa==0.10.2.post1' && \
   python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
