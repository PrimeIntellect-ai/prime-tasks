#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import re
import secrets
import subprocess
import tempfile


def test_downtime_frames_count():
    path = "/home/user/downtime_frames.txt"
    assert os.path.isfile(path), f"{path} does not exist"
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "45", f"Expected downtime_frames.txt to contain '45', but got '{content}'"


def test_rust_classifier_adversarial_corpus():
    project = "/home/user/classifier"
    manifest = os.path.join(project, "Cargo.toml")
    assert os.path.isfile(manifest), "Classifier Cargo.toml does not exist"

    metadata_result = subprocess.run(
        ["cargo", "metadata", "--no-deps", "--format-version", "1", "--manifest-path", manifest],
        capture_output=True,
        text=True,
    )
    assert metadata_result.returncode == 0, f"Invalid Cargo project: {metadata_result.stderr}"
    metadata = json.loads(metadata_result.stdout)
    bin_targets = [
        target
        for package in metadata.get("packages", [])
        for target in package.get("targets", [])
        if "bin" in target.get("kind", []) and target.get("name") == "classifier"
    ]
    assert bin_targets, "Cargo project does not define a Rust binary target named classifier"
    assert all(target.get("src_path", "").endswith(".rs") for target in bin_targets), "Classifier binary target is not Rust source"

    debug_bin = "/home/user/classifier/target/debug/classifier"
    release_bin = "/home/user/classifier/target/release/classifier"
    for candidate in (debug_bin, release_bin):
        if os.path.lexists(candidate):
            os.remove(candidate)

    build = subprocess.run(
        ["cargo", "build", "--manifest-path", manifest, "--bin", "classifier"],
        capture_output=True,
        text=True,
    )
    assert build.returncode == 0, f"Rust classifier failed to compile: {build.stderr}"

    executable = None
    if os.path.isfile(debug_bin) and os.access(debug_bin, os.X_OK):
        executable = debug_bin
    elif os.path.isfile(release_bin) and os.access(release_bin, os.X_OK):
        executable = release_bin

    assert executable is not None, "Could not find compiled Rust classifier executable in target/debug or target/release"
    with open(executable, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Compiled classifier is not a native executable"

    clean_dir = "/app/corpus/clean/"
    evil_dir = "/app/corpus/evil/"
    clean_files = glob.glob(os.path.join(clean_dir, "*"))
    evil_files = glob.glob(os.path.join(evil_dir, "*"))

    assert len(clean_files) > 0, "No clean corpus files found"
    assert len(evil_files) > 0, "No evil corpus files found"

    clean_failures = []
    for f in clean_files:
        result = subprocess.run([executable, f], capture_output=True, text=True)
        out = result.stdout.strip()
        if result.returncode != 0 or out != "CLEAN":
            clean_failures.append(os.path.basename(f))

    evil_failures = []
    for f in evil_files:
        result = subprocess.run([executable, f], capture_output=True, text=True)
        out = result.stdout.strip()
        if result.returncode != 0 or out != "EVIL":
            evil_failures.append(os.path.basename(f))

    error_msgs = []
    if evil_failures:
        error_msgs.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed: {', '.join(evil_failures)}")
    if clean_failures:
        error_msgs.append(f"{len(clean_failures)} of {len(clean_files)} clean modified/flagged: {', '.join(clean_failures)}")
    assert not error_msgs, "Classifier failed: " + "; ".join(error_msgs)

    # Exercise freshly generated, neutrally named files so classification cannot
    # be inferred from the fixed corpus paths or filenames.
    with tempfile.TemporaryDirectory(prefix="classifier_cases_") as case_dir:
        ip_a = f"10.{secrets.randbelow(200) + 1}.{secrets.randbelow(250) + 1}.{secrets.randbelow(250) + 1}"
        ip_b = f"172.{secrets.randbelow(15) + 16}.{secrets.randbelow(250) + 1}.{secrets.randbelow(250) + 1}"
        high_count = secrets.randbelow(450) + 51
        low_count = secrets.randbelow(51)
        cases = [
            (f"Routine health check from {ip_a}\nNo packet loss observed\n", "CLEAN"),
            (f"Connection spike\nIP {ip_a}: {low_count} connections\n", "CLEAN"),
            (f"Informational note: udp flood wording was lowercase\nIP {ip_b}: 12 connections\n", "CLEAN"),
            (f"Alert token {secrets.token_hex(8)}: UDP FLOOD detected on uplink\n", "EVIL"),
            (f"Connection spike\nIP {ip_b}: {high_count} connections\n", "EVIL"),
        ]
        random.SystemRandom().shuffle(cases)
        for body, expected in cases:
            path = os.path.join(case_dir, secrets.token_hex(12) + ".dat")
            with open(path, "w") as f:
                f.write(body)
            result = subprocess.run([executable, path], capture_output=True, text=True)
            assert result.returncode == 0, f"Classifier exited {result.returncode} for generated input"
            assert result.stdout.strip() == expected, (
                f"Generated input expected {expected}, got {result.stdout!r}"
            )


def test_mail_image_size():
    img_path = "/home/user/mail.img"
    assert os.path.isfile(img_path), f"{img_path} does not exist"
    size = os.path.getsize(img_path)
    expected_size = 50 * 1024 * 1024
    assert size == expected_size, f"Expected {img_path} to be {expected_size} bytes, got {size}"


def test_fstab_line():
    fstab_path = "/home/user/fstab_line.txt"
    assert os.path.isfile(fstab_path), f"{fstab_path} does not exist"
    with open(fstab_path, "r") as f:
        content = f.read().strip()

    # Preserve the original accepted forms while also accepting defaults,loop.
    pattern = r"/home/user/mail\.img\s+/home/user/mail_backup\s+ext4\s+(?:loop,?(?:defaults)?|defaults,loop)\s+0\s+0"
    assert re.search(pattern, content), f"fstab line in {fstab_path} does not match expected format. Got: {content}"


def test_mail_backup_dir():
    dir_path = "/home/user/mail_backup"
    assert os.path.isdir(dir_path), f"Directory {dir_path} does not exist"


def _rootless_podman(*args):
    return subprocess.run(
        ["runuser", "-u", "user", "--", "podman", *args],
        capture_output=True,
        text=True,
    )


def test_podman_container_running():
    result = _rootless_podman("ps", "--format", "{{.Names}}")
    assert result.returncode == 0, f"Could not query rootless Podman: {result.stderr}"
    names = result.stdout.splitlines()
    assert "mail_spooler" in names, "Rootless container 'mail_spooler' is not running"


def test_podman_container_configuration_and_mount():
    result = _rootless_podman("inspect", "mail_spooler")
    assert result.returncode == 0, "Failed to inspect rootless container 'mail_spooler'"

    data = json.loads(result.stdout)
    assert len(data) == 1, "Expected exactly one inspected mail_spooler container"
    info = data[0]
    assert info.get("Name", "").lstrip("/") == "mail_spooler", "Container name is not exactly mail_spooler"

    state = info.get("State", {})
    assert state.get("Running") is True or state.get("Status") == "running", "Container 'mail_spooler' is not running"

    config = info.get("Config", {})
    image_values = [info.get("ImageName", ""), config.get("Image", "")]
    create_command = config.get("CreateCommand", []) or []
    image_ok = any(
        value == "alpine:latest" or value.endswith("/alpine:latest")
        for value in image_values + [str(x) for x in create_command]
    )
    assert image_ok, "Container 'mail_spooler' does not use alpine:latest"

    cmd = config.get("Cmd") or []
    path_args = [info.get("Path")] + list(info.get("Args") or [])
    assert cmd == ["sleep", "3600"] or path_args == ["sleep", "3600"], (
        f"Container command must be exactly sleep 3600, got Cmd={cmd!r}, Path/Args={path_args!r}"
    )

    mounts = info.get("Mounts", [])
    found_mount = False
    for mount in mounts:
        if mount.get("Source") == "/home/user/mail_backup" and mount.get("Destination") == "/var/mail":
            found_mount = True
            break
    assert found_mount, "Container 'mail_spooler' does not have the correct bind mount from /home/user/mail_backup to /var/mail"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
