#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import json
import os
import pwd
import shutil
import subprocess
import tempfile
import zipfile

import numpy as np
import scipy.io.wavfile as wavfile


def _remove_path(path):
    if os.path.islink(path) or os.path.isfile(path):
        os.unlink(path)
    elif os.path.isdir(path):
        shutil.rmtree(path)


def _python_scripts():
    scripts = []
    for root in ("/home/user", "/app"):
        for current, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in {"extracted", "__pycache__", ".git", ".venv", "venv"}]
            for name in files:
                path = os.path.join(current, name)
                is_python = name.endswith(".py")
                if not is_python:
                    try:
                        with open(path, "rb") as f:
                            first_line = f.readline(256).lower()
                        is_python = first_line.startswith(b"#!") and b"python" in first_line
                    except OSError:
                        continue
                if is_python and os.path.isfile(path) and not os.path.islink(path):
                    scripts.append(path)
    return sorted(set(scripts))


def _demote_to_user():
    account = pwd.getpwnam("user")
    os.setgroups([])
    os.setgid(account.pw_gid)
    os.setuid(account.pw_uid)


def test_safe_extraction():
    extracted_dir = "/home/user/extracted"
    assert os.path.exists(extracted_dir), f"Directory {extracted_dir} does not exist."

    # Check safe files
    assert os.path.exists(os.path.join(extracted_dir, "transmission.wav")), "transmission.wav was not extracted."
    assert os.path.exists(os.path.join(extracted_dir, "metadata.json")), "metadata.json was not extracted."

    # Check malicious files are absent from the system
    assert not os.path.exists("/home/user/evil.txt"), "Malicious file evil.txt was extracted outside the target directory."
    assert not os.path.exists("/etc/passwd_overwrite"), "Malicious file passwd_overwrite was extracted outside the target directory."

    # Check they weren't extracted inside the target dir under sanitized names
    assert not os.path.exists(os.path.join(extracted_dir, "evil.txt")), "Malicious file evil.txt was extracted inside the target directory. It should have been skipped."
    assert not os.path.exists(os.path.join(extracted_dir, "passwd_overwrite")), "Malicious file passwd_overwrite was extracted inside the target directory. It should have been skipped."

    assert os.path.isdir(extracted_dir) and not os.path.islink(extracted_dir)
    with zipfile.ZipFile("/app/artifacts.zip", "r") as zf:
        for name in ("transmission.wav", "metadata.json"):
            output = os.path.join(extracted_dir, name)
            assert os.path.isfile(output) and not os.path.islink(output)
            with open(output, "rb") as f:
                assert f.read() == zf.read(name), f"Extracted {name} does not match the archive entry."

    # Execute the submitted Python extraction script against a second archive whose
    # expected safe and unsafe paths are derived here rather than fixed by setup.
    scripts = _python_scripts()
    assert scripts, "No Python script implementing safe extraction was found."

    rate = 8000
    audio = np.arange(64, dtype=np.int16)
    wav_buffer = io.BytesIO()
    wavfile.write(wav_buffer, rate, audio)
    expected = {
        "transmission.wav": wav_buffer.getvalue(),
        "metadata.json": json.dumps({
            "message_start_sec": 0.0,
            "message_end_sec": 0.004,
            "smoothing_window": 3,
        }).encode("utf-8"),
        "nested/ok.bin": b"nested-safe-payload\x00\xff",
    }
    malicious = {
        "../zip_slip_probe_a_91c8.txt": b"bad-a",
        "../../../../tmp/zip_slip_probe_b_91c8.txt": b"bad-b",
        "/tmp/zip_slip_probe_c_91c8.txt": b"bad-c",
        "nested/../../zip_slip_probe_d_91c8.txt": b"bad-d",
        "../extracted_evil_91c8/probe.txt": b"bad-e",
    }
    outside_paths = [
        "/home/user/zip_slip_probe_a_91c8.txt",
        "/tmp/zip_slip_probe_b_91c8.txt",
        "/tmp/zip_slip_probe_c_91c8.txt",
        "/home/user/zip_slip_probe_d_91c8.txt",
        "/home/user/extracted_evil_91c8",
    ]

    archive_path = "/app/artifacts.zip"
    with open(archive_path, "rb") as f:
        original_archive = f.read()
    backup_root = tempfile.mkdtemp(prefix="extract-backup-")
    backup_extracted = os.path.join(backup_root, "extracted")
    shutil.copytree(extracted_dir, backup_extracted, symlinks=True)

    successful_script = None
    try:
        with zipfile.ZipFile(archive_path, "w") as zf:
            for name, contents in expected.items():
                zf.writestr(name, contents)
            for name, contents in malicious.items():
                zf.writestr(name, contents)

        account = pwd.getpwnam("user")
        for script in scripts:
            _remove_path(extracted_dir)
            os.mkdir(extracted_dir)
            os.chown(extracted_dir, account.pw_uid, account.pw_gid)
            for path in outside_paths:
                _remove_path(path)

            try:
                subprocess.run(
                    ["python3", script],
                    cwd=os.path.dirname(script) or "/home/user",
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=20,
                    check=False,
                    preexec_fn=_demote_to_user,
                )
            except (OSError, subprocess.TimeoutExpired):
                continue

            actual_files = set()
            unsafe_object = False
            for current, dirs, files in os.walk(extracted_dir, followlinks=False):
                if any(os.path.islink(os.path.join(current, d)) for d in dirs):
                    unsafe_object = True
                for filename in files:
                    path = os.path.join(current, filename)
                    if os.path.islink(path):
                        unsafe_object = True
                    actual_files.add(os.path.relpath(path, extracted_dir).replace(os.sep, "/"))

            valid = not unsafe_object and actual_files == set(expected)
            if valid:
                for name, contents in expected.items():
                    path = os.path.join(extracted_dir, *name.split("/"))
                    if not os.path.isfile(path) or os.path.islink(path):
                        valid = False
                        break
                    with open(path, "rb") as f:
                        if f.read() != contents:
                            valid = False
                            break
            if valid and any(os.path.lexists(path) for path in outside_paths):
                valid = False

            if valid:
                successful_script = script
                break

        assert successful_script is not None, (
            "No submitted Python script safely extracted a fresh archive while "
            "skipping all entries whose resolved paths escaped the target directory."
        )
    finally:
        with open(archive_path, "wb") as f:
            f.write(original_archive)
        _remove_path(extracted_dir)
        shutil.copytree(backup_extracted, extracted_dir, symlinks=True)
        shutil.rmtree(backup_root, ignore_errors=True)
        for path in outside_paths:
            _remove_path(path)


def test_audio_processing():
    agent_output = "/home/user/clean_transmission.wav"
    assert os.path.exists(agent_output), f"Agent output file {agent_output} does not exist."

    # Load original data and metadata directly from the zip file to ensure pristine reference
    zip_path = "/app/artifacts.zip"
    with zipfile.ZipFile(zip_path, "r") as zf:
        with zf.open("metadata.json") as f:
            metadata = json.load(f)
        with zf.open("transmission.wav") as f:
            orig_rate, orig_data = wavfile.read(io.BytesIO(f.read()))

    start_sec = metadata["message_start_sec"]
    end_sec = metadata["message_end_sec"]
    window = metadata["smoothing_window"]

    # Calculate crop indices
    start_idx = int(start_sec * orig_rate)
    end_idx = int(end_sec * orig_rate)

    # Crop audio
    cropped_data = orig_data[start_idx:end_idx]

    # Apply moving average filter
    # Using cumsum for efficient moving average calculation over potentially large arrays
    if cropped_data.ndim == 1:
        cumsum = np.cumsum(np.insert(cropped_data.astype(float), 0, 0))
        ref_data = np.zeros_like(cropped_data, dtype=float)
        for i in range(len(cropped_data)):
            start_w = max(0, i - window + 1)
            end_w = i + 1
            ref_data[i] = (cumsum[end_w] - cumsum[start_w]) / (end_w - start_w)
    else:
        # Handle multi-channel audio if present
        cumsum = np.cumsum(np.insert(cropped_data.astype(float), 0, 0, axis=0), axis=0)
        ref_data = np.zeros_like(cropped_data, dtype=float)
        for i in range(len(cropped_data)):
            start_w = max(0, i - window + 1)
            end_w = i + 1
            ref_data[i] = (cumsum[end_w] - cumsum[start_w]) / (end_w - start_w)

    # Load agent data
    agent_rate, agent_data = wavfile.read(agent_output)

    assert agent_rate == orig_rate, f"Agent sample rate {agent_rate} does not match original {orig_rate}."
    assert len(agent_data) == len(ref_data), f"Agent audio length {len(agent_data)} does not match expected {len(ref_data)}."

    # Calculate Mean Squared Error
    mse = np.mean((agent_data.astype(float) - ref_data)**2)

    threshold = 1.0
    assert mse <= threshold, f"MSE {mse:.4f} exceeds threshold of {threshold}. Audio processing (cropping or smoothing) is incorrect."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
