#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import glob
import gzip
import os
import re
import subprocess
import time
import uuid


def run_classifier(path):
    return subprocess.run(
        ["/home/user/classifier", path],
        capture_output=True,
        text=True,
        timeout=10,
    )


def assert_classification(path, evil):
    result = run_classifier(path)
    expected_output = "EVIL" if evil else "CLEAN"
    expected_code = 1 if evil else 0
    assert result.returncode == expected_code, (
        f"Wrong exit code for {path}: expected {expected_code}, got {result.returncode}; "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert result.stdout in (expected_output, expected_output + "\n"), (
        f"Wrong or extra stdout for {path}: expected exactly {expected_output!r}, "
        f"got {result.stdout!r}"
    )


def test_classifier_adversarial_corpus():
    classifier_path = "/home/user/classifier"
    source_path = "/home/user/classifier.go"
    assert os.path.isfile(source_path), f"Classifier source missing: {source_path}"
    assert os.path.isfile(classifier_path), f"Classifier binary missing: {classifier_path}"
    assert os.access(classifier_path, os.X_OK), f"Classifier is not executable: {classifier_path}"

    with open(classifier_path, "rb") as f:
        binary = f.read()
    assert binary.startswith(b"\x7fELF"), "Classifier is not a compiled ELF binary"
    assert b"Go buildinf:" in binary, "Classifier does not contain Go build information"

    evil_dir = "/home/user/corpus/evil"
    clean_dir = "/home/user/corpus/clean"
    evil_files = glob.glob(os.path.join(evil_dir, "*.log"))
    clean_files = glob.glob(os.path.join(clean_dir, "*.log"))

    assert len(evil_files) > 0, "No evil corpus files found."
    assert len(clean_files) > 0, "No clean corpus files found."

    evil_bypassed = []
    for evil_file in evil_files:
        result = subprocess.run([classifier_path, evil_file], capture_output=True, text=True)
        if result.returncode != 1 or result.stdout.strip() != "EVIL":
            evil_bypassed.append(os.path.basename(evil_file))

    clean_modified = []
    for clean_file in clean_files:
        result = subprocess.run([classifier_path, clean_file], capture_output=True, text=True)
        if result.returncode != 0 or result.stdout.strip() != "CLEAN":
            clean_modified.append(os.path.basename(clean_file))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")
    assert not errors, "Classifier failed corpus tests:\n" + "\n".join(errors)

    dynamic_dir = f"/tmp/classifier_dynamic_{uuid.uuid4().hex}"
    os.makedirs(dynamic_dir)
    cases = [
        ("looks_clean_monitor.log", b"boot\n\x01c\nstatus: system_reset requested\n", True),
        ("looks_clean_quit.log", b"boot\n\x01c\nquit\n", True),
        ("looks_clean_oom.log", b"x\nOut of memory: Killed process 987654 (sshd)\ny\n", True),
        ("looks_clean_hex.log", b"prefix 41414141414141414141414141414141 suffix\n", True),
        ("evil_named_but_safe.log", b"system_reset\n\x01c\nnormal boot\n", False),
        ("evil_intervening_line.log", b"\x01c\nintervening\nsystem_reset\n", False),
        ("evil_short_hex.log", b"414141414141414141414141414141\n", False),
        ("evil_lower_hex.log", b"4141414141414141414141414141414a\n", False),
        ("evil_bad_oom.log", b"Out of memory: Killed process twelve (sshd)\n", False),
        ("evil_ordinary.log", b"QEMU boot complete\nsshd started\n", False),
    ]
    for name, data, evil in cases:
        path = os.path.join(dynamic_dir, name)
        with open(path, "wb") as f:
            f.write(data)
        assert_classification(path, evil)

    for args in ([], [cases[0][0], cases[1][0]]):
        expanded = [os.path.join(dynamic_dir, arg) for arg in args]
        result = subprocess.run([classifier_path] + expanded, capture_output=True, text=True, timeout=10)
        assert result.returncode != 0, f"Classifier accepted invalid argument count {len(args)}"
        assert result.stdout.strip() not in ("EVIL", "CLEAN"), (
            f"Classifier produced a classification with invalid argument count {len(args)}"
        )

    missing = os.path.join(dynamic_dir, "does_not_exist.log")
    result = subprocess.run([classifier_path, missing], capture_output=True, text=True, timeout=10)
    assert result.returncode != 0, "Classifier succeeded for a nonexistent input file"
    assert result.stdout.strip() not in ("EVIL", "CLEAN"), "Classifier classified a nonexistent file"


def test_log_forwarding_flow():
    forwarder_script = "/home/user/forwarder.sh"
    assert os.path.isfile(forwarder_script), f"Forwarder script missing: {forwarder_script}"
    assert os.access(forwarder_script, os.X_OK), f"Forwarder script is not executable: {forwarder_script}"

    qemu_log = "/tmp/qemu.log"
    aggregated_log = "/tmp/aggregated.log"
    test_string = "VERIFICATION_STRING_1337"

    with open(qemu_log, "a") as f:
        f.write(f"\n{test_string}\n")

    time.sleep(2)
    assert os.path.isfile(aggregated_log), f"Aggregated log missing: {aggregated_log}"
    with open(aggregated_log, "r") as f:
        content = f.read()
    assert test_string in content, (
        f"Test string '{test_string}' not found in {aggregated_log}. "
        "Forwarding pipeline is not working."
    )


def readable_contents(path):
    try:
        if os.path.getsize(path) > 3 * 1024 * 1024:
            return b""
        if path.endswith(".gz"):
            with gzip.open(path, "rb") as f:
                return f.read()
        with open(path, "rb") as f:
            return f.read()
    except (OSError, EOFError):
        return b""


def rotation_candidates():
    paths = set(glob.glob("/tmp/qemu.log*"))
    paths.update(glob.glob("/home/user/**/qemu.log*", recursive=True))
    result = []
    quarantine = os.path.realpath("/home/user/backups/quarantine")
    for path in paths:
        if os.path.realpath(path) == os.path.realpath("/tmp/qemu.log"):
            continue
        if os.path.realpath(path).startswith(quarantine + os.sep):
            continue
        if os.path.isfile(path):
            result.append(path)
    return result


def files_containing(marker, paths):
    needle = marker.encode()
    return [path for path in paths if needle in readable_contents(path)]


def run_logrotate(config, state):
    result = subprocess.run(
        ["logrotate", "-s", state, config],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"logrotate failed with code {result.returncode}:\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )


def test_logrotate_config():
    config_path = "/home/user/qemu-logrotate.conf"
    assert os.path.isfile(config_path), f"Logrotate config missing: {config_path}"

    with open(config_path, "r") as f:
        content = f.read()

    assert re.search(r"size\s+1M", content), "Logrotate config missing 'size 1M'"
    assert re.search(r"rotate\s+5", content), "Logrotate config missing 'rotate 5'"
    assert "compress" in content, "Logrotate config missing 'compress'"
    assert "prerotate" in content, "Logrotate config missing 'prerotate' block"
    assert "/home/user/classifier" in content, "Logrotate config prerotate block missing classifier invocation"

    quarantine = "/home/user/backups/quarantine"
    assert os.path.isdir(quarantine), f"Quarantine directory missing: {quarantine}"

    # Stop only the supplied log generator so size and rotation checks are deterministic.
    subprocess.run(["pkill", "-f", "QEMU log entry"], capture_output=True)
    time.sleep(0.3)

    for path in glob.glob("/tmp/qemu.log.*") + glob.glob("/tmp/qemu.log-*"):
        try:
            os.remove(path)
        except OSError:
            pass

    state = f"/tmp/logrotate_state_{uuid.uuid4().hex}"
    token = uuid.uuid4().hex

    small_marker = f"SMALL_CLEAN_{token}"
    with open("/tmp/qemu.log", "wb") as f:
        f.write((small_marker + "\nordinary log line\n").encode())
    run_logrotate(config_path, state)
    assert not files_containing(small_marker, rotation_candidates()), (
        "A log smaller than 1M was rotated"
    )
    assert small_marker.encode() in open("/tmp/qemu.log", "rb").read(), (
        "The sub-threshold live log was removed or replaced"
    )

    markers = []
    for index in range(7):
        marker = f"ROTATION_{index}_{token}"
        markers.append(marker)
        if index == 1:
            header = f"{marker}\nOut of memory: Killed process 24680 (sshd)\n"
        else:
            header = f"{marker}\nnormal QEMU log data\n"
        payload = header.encode() + b"z" * (1024 * 1024 + 4096)
        with open("/tmp/qemu.log", "wb") as f:
            f.write(payload)
        run_logrotate(config_path, state)
        assert files_containing(marker, rotation_candidates()), (
            f"Oversized log containing {marker} was not actually rotated"
        )

        quarantine_files = [p for p in glob.glob(quarantine + "/**", recursive=True) if os.path.isfile(p)]
        if index == 1:
            assert files_containing(marker, quarantine_files), (
                "An EVIL log was not copied to the quarantine directory before rotation"
            )
        else:
            assert not files_containing(marker, quarantine_files), (
                "A CLEAN log was incorrectly copied to quarantine"
            )

    candidates = rotation_candidates()
    retained = [marker for marker in markers if files_containing(marker, candidates)]
    assert len(retained) == 5, (
        f"Expected exactly 5 retained rotated logs after 7 rotations, found markers: {retained}"
    )
    assert retained == markers[-5:], (
        f"Rotation did not retain the newest 5 backups: found {retained}"
    )

    compressed_marker_backups = []
    for path in candidates:
        if path.endswith(".gz") and any(marker.encode() in readable_contents(path) for marker in markers):
            compressed_marker_backups.append(path)
    assert compressed_marker_backups, "No retained rotated log was compressed"

    quarantine_files = [p for p in glob.glob(quarantine + "/**", recursive=True) if os.path.isfile(p)]
    assert not files_containing(small_marker, quarantine_files), (
        "A clean sub-threshold log was incorrectly quarantined"
    )

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
