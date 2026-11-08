#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import random
import re
import subprocess
import tempfile
import uuid
import pytest

HOME = "/home/user"
IMAGE = f"{HOME}/alert_volume.img"
DATA = f"{HOME}/alert_data"
PROJECT = f"{HOME}/alert_classifier"


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def test_storage_setup():
    assert os.path.isfile(IMAGE), f"{IMAGE} does not exist"
    assert os.path.getsize(IMAGE) == 50 * 1024 * 1024, "alert_volume.img is not exactly 50 MiB"

    fs_type = run(["blkid", "-s", "TYPE", "-o", "value", IMAGE])
    assert fs_type.returncode == 0 and fs_type.stdout.strip() == "ext4", "alert_volume.img is not ext4"

    # Retain the original mount assertion, then verify that alert_data itself is
    # a mounted filesystem backed by the requested image rather than a substring
    # planted elsewhere in mount output.
    mount_output = run(["mount"]).stdout
    assert DATA in mount_output or "fuse2fs" in mount_output, f"{DATA} is not mounted"

    mounted = run(["findmnt", "-rn", "-T", DATA, "-o", "TARGET,FSTYPE,SOURCE"])
    assert mounted.returncode == 0 and mounted.stdout.strip(), f"{DATA} is not a mountpoint"
    fields = mounted.stdout.strip().split(None, 2)
    assert len(fields) == 3, f"Could not inspect mount for {DATA}: {mounted.stdout!r}"
    target, mounted_type, source = fields
    assert os.path.realpath(target) == os.path.realpath(DATA), f"{DATA} is not the actual mount target"
    assert "ext" in mounted_type.lower() or "fuse2fs" in mounted_type.lower(), f"Unexpected mounted filesystem type: {mounted_type}"
    assert os.path.basename(IMAGE) in source or os.path.realpath(source) == os.path.realpath(IMAGE), f"Mount is not backed by {IMAGE}: {source}"

    assert os.path.islink(f"{HOME}/current_alerts"), f"{HOME}/current_alerts is not a symlink"
    assert os.readlink(f"{HOME}/current_alerts") == f"{DATA}/incoming", "Symlink does not point to alert_data/incoming"

    for d in ["incoming", "processing", "archive"]:
        assert os.path.isdir(f"{DATA}/{d}"), f"Directory {DATA}/{d} does not exist"


def classifier_binary():
    release = f"{PROJECT}/target/release/alert-filter"
    debug = f"{PROJECT}/target/debug/alert-filter"
    if os.path.isfile(release):
        existing = release
    elif os.path.isfile(debug):
        existing = debug
    else:
        pytest.fail("Rust binary alert-filter not found in release or debug target directories")

    assert os.path.isfile(f"{PROJECT}/Cargo.toml"), "Cargo.toml is missing"
    assert os.path.isfile(f"{PROJECT}/src/main.rs"), "Rust source src/main.rs is missing"

    # Rebuild from the submitted Cargo project so a planted non-Rust executable
    # in target/ cannot satisfy the behavioral checks.
    build = run([
        "runuser", "-u", "user", "--", "env",
        f"HOME={HOME}", f"CARGO_HOME={HOME}/.cargo",
        "cargo", "build", "--release", "--manifest-path", f"{PROJECT}/Cargo.toml"
    ], timeout=180)
    assert build.returncode == 0, f"Cargo project failed to build:\n{build.stdout}\n{build.stderr}"
    assert os.path.isfile(release) and os.access(release, os.X_OK), "Built alert-filter is not executable"
    return release


def exercise(binary, text, expected_clean):
    with tempfile.TemporaryDirectory() as tmpdir:
        name = f"input-{uuid.uuid4().hex}.txt"
        input_path = os.path.join(tmpdir, name)
        output_dir = os.path.join(tmpdir, "output")
        os.mkdir(output_dir)
        with open(input_path, "w") as f:
            f.write(text)

        result = run([binary, input_path, output_dir])
        output_path = os.path.join(output_dir, name)
        if expected_clean:
            assert result.returncode == 0, f"Genuine alert was rejected: {text!r}"
            assert os.path.isfile(output_path), f"Genuine alert was not copied: {text!r}"
            with open(output_path) as f:
                assert f.read() == text, "Copied alert content was changed"
        else:
            assert result.returncode == 1, f"False alarm was accepted: {text!r}"
            assert not os.path.exists(output_path), f"False alarm was copied: {text!r}"


def test_rust_binary_adversarial_corpus():
    binary = classifier_binary()
    clean_dir = "/app/corpora/clean"
    evil_dir = "/app/corpora/evil"
    clean_files = [f for f in os.listdir(clean_dir) if f.endswith(".txt")]
    evil_files = [f for f in os.listdir(evil_dir) if f.endswith(".txt")]
    failed_clean = []
    failed_evil = []

    # Retain all original corpus assertions.
    with tempfile.TemporaryDirectory() as tmpdir:
        for cf in clean_files:
            input_file = os.path.join(clean_dir, cf)
            res = run([binary, input_file, tmpdir])
            if res.returncode != 0:
                failed_clean.append(cf)
            elif not os.path.isfile(os.path.join(tmpdir, cf)):
                failed_clean.append(cf + " (not copied)")

        for ef in evil_files:
            input_file = os.path.join(evil_dir, ef)
            res = run([binary, input_file, tmpdir])
            if res.returncode != 1:
                failed_evil.append(ef)

    assert not failed_clean, f"{len(failed_clean)} of {len(clean_files)} clean modified/rejected: {', '.join(failed_clean)}"
    assert not failed_evil, f"{len(failed_evil)} of {len(evil_files)} evil bypassed: {', '.join(failed_evil)}"

    # Exercise the same corpus patterns using unpredictable values, formatting,
    # and filenames. Expected labels are generated by the test, not supplied by
    # the classifier or inferred from paths.
    n1 = random.randint(91, 99)
    n2 = random.randint(96, 99)
    volume = random.choice(["Y", "Z", "DATA", "BACKUP"])
    shard = random.choice(["eight", "nine", "ten", "eleven"])
    cases = [
        (f"CPU utilization exceeded {n1}%", True),
        (f"  disk SPACE critical on volume {volume}\n", True),
        (f"Memory usage at {n2} percent", True),
        (f"Warning. Database shard {shard} has reached maximum IOPS capacity.", True),
        ("TEST message please ignore", False),
        ("Printer is out of paper", False),
        ("A software update is available", False),
    ]
    random.shuffle(cases)
    for text, expected_clean in cases:
        exercise(binary, text, expected_clean)


def test_audio_transcription():
    transcript_path = f"{DATA}/archive/sample_transcript.txt"
    assert os.path.isfile(transcript_path), f"Transcript not found at {transcript_path}"
    with open(transcript_path, "r") as f:
        content = f.read().strip().lower()
    expected = "warning. database shard seven has reached maximum iops capacity."
    assert expected in content, f"Transcript content incorrect. Got: {content}"


def test_service_management():
    wrapper = f"{HOME}/process_alerts.sh"
    service = f"{HOME}/.config/systemd/user/alert-processor.service"
    timer = f"{HOME}/.config/systemd/user/alert-processor.timer"
    assert os.path.isfile(wrapper), "process_alerts.sh is missing"
    assert os.path.isfile(service), "alert-processor.service is missing"
    assert os.path.isfile(timer), "alert-processor.timer is missing"

    service_text = open(service).read()
    timer_text = open(timer).read()
    assert re.search(r"(?mi)^\s*Type\s*=\s*oneshot\s*$", service_text), "Service is not Type=oneshot"
    assert re.search(r"(?mi)^\s*ExecStart\s*=.*?/home/user/process_alerts\.sh(?:\s|$)", service_text), "Service does not execute process_alerts.sh"

    unit_match = re.search(r"(?mi)^\s*Unit\s*=\s*(\S+)\s*$", timer_text)
    assert unit_match is None or unit_match.group(1) == "alert-processor.service", "Timer targets the wrong service"
    minute_schedule = (
        re.search(r"(?mi)^\s*OnUnitActiveSec\s*=\s*(?:1\s*min(?:ute)?|60\s*(?:s|sec(?:ond)?s?))\s*$", timer_text)
        or re.search(r"(?mi)^\s*OnCalendar\s*=\s*(?:minutely|\*-\*-\*\s+\*:\*:00)\s*$", timer_text)
    )
    assert minute_schedule, "Timer is not configured to run every minute"

    wants = f"{HOME}/.config/systemd/user/timers.target.wants/alert-processor.timer"
    assert os.path.islink(wants) and os.path.realpath(wants) == os.path.realpath(timer), "Timer is not enabled"

    # Retain the original active-timer assertion.
    res = run(["systemctl", "--user", "is-active", "alert-processor.timer"])
    assert res.stdout.strip() == "active", "alert-processor.timer is not active"

    # Put a novel alert in incoming and start the submitted service. This proves
    # that the service definition invokes the wrapper and processes real input;
    # a pre-created archive transcript cannot satisfy this check.
    name = f"service-{uuid.uuid4().hex}.txt"
    incoming = f"{DATA}/incoming/{name}"
    archived = f"{DATA}/archive/{name}"
    text = f"CPU utilization exceeded {random.randint(91, 99)}%\n"
    assert not os.path.exists(archived)
    with open(incoming, "w") as f:
        f.write(text)
    user = pwd.getpwnam("user")
    os.chown(incoming, user.pw_uid, user.pw_gid)

    started = run(["systemctl", "--user", "start", "alert-processor.service"], timeout=30)
    assert started.returncode == 0, f"alert-processor.service failed: {started.stderr}"
    assert not os.path.exists(incoming), "Service did not consume the incoming transcript"
    assert os.path.isfile(archived), "Service did not archive the genuine alert"
    with open(archived) as f:
        assert f.read() == text, "Service changed the archived transcript"


def test_final_output():
    status_file = f"{HOME}/status.log"
    assert os.path.isfile(status_file), f"Status file {status_file} not found"
    with open(status_file, "r") as f:
        content = f.read().strip()
    assert content == "PIPELINE ACTIVE", f"Status file content incorrect. Got: {content}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
