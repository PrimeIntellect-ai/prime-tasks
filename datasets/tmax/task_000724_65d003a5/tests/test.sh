#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shlex
import subprocess
import tarfile
import tempfile
import uuid


def test_drop_count():
    count_file = "/home/user/drop_count.txt"
    assert os.path.exists(count_file), f"File {count_file} does not exist."
    with open(count_file, "r") as f:
        content = f.read().strip()
    assert content == "14", f"Expected drop count to be '14', but got '{content}'."

    video = "/app/switch_monitor.mp4"
    result = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", video, "-vf", "scale=1:1", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
        capture_output=True,
        check=True,
        timeout=30,
    )
    pixels = result.stdout
    assert len(pixels) % 3 == 0, "Could not decode the video into complete RGB frames."
    derived_count = sum(
        1 for i in range(0, len(pixels), 3)
        if pixels[i] > 200 and pixels[i + 1] < 50 and pixels[i + 2] < 50
    )
    assert int(content) == derived_count, (
        f"Drop count {content} does not match the {derived_count} red frames decoded from the video."
    )


def run_classifier(script_path, path):
    return subprocess.run([script_path, path], capture_output=True, timeout=3).returncode


def test_log_classifier_adversarial():
    script_path = "/home/user/log_classifier.sh"
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    assert os.path.isfile(script_path), f"Script {script_path} is not a regular file."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    clean_failed = []
    for cf in clean_files:
        if run_classifier(script_path, cf) != 0:
            clean_failed.append(os.path.basename(cf))

    evil_failed = []
    for ef in evil_files:
        if run_classifier(script_path, ef) != 1:
            evil_failed.append(os.path.basename(ef))

    error_messages = []
    if clean_failed:
        error_messages.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failed)}")
    if evil_failed:
        error_messages.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed/accepted: {', '.join(evil_failed)}")
    assert not error_messages, "Adversarial corpus test failed: " + "; ".join(error_messages)

    safe = set(b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 -_:.[]")
    # Existing clean logs are newline-terminated, so line-feed is accepted as a record separator.
    with tempfile.TemporaryDirectory(prefix="classifier-check-" + uuid.uuid4().hex + "-") as td:
        cases = []
        clean_payloads = [
            b"",
            bytes(sorted(safe)),
            b"[2026-09-11 12:34:56] Interface core_1 state-UP: clean.log\n",
            b"A9 _-:.[]\nSecond safe line 42",
        ]
        for payload in clean_payloads:
            path = os.path.join(td, uuid.uuid4().hex)
            with open(path, "wb") as f:
                f.write(payload)
            cases.append((path, 0, payload))

        # Exercise every byte outside the permitted set, at unpredictable paths.
        for value in range(256):
            if value in safe or value == 10:
                continue
            payload = b"SafePrefix" + bytes([value]) + b"SafeSuffix"
            path = os.path.join(td, uuid.uuid4().hex)
            with open(path, "wb") as f:
                f.write(payload)
            cases.append((path, 1, payload))

        random.SystemRandom().shuffle(cases)
        failures = []
        for path, expected, payload in cases:
            actual = run_classifier(script_path, path)
            if actual != expected:
                failures.append(
                    f"payload {payload!r}: expected exit {expected}, got {actual}"
                )
                if len(failures) >= 10:
                    break
        assert not failures, "Classifier failed content-derived cases: " + "; ".join(failures)


def test_backup_tarball():
    backup_path = "/home/user/backup.tar.gz"
    assert os.path.exists(backup_path), f"Backup tarball {backup_path} does not exist."
    assert tarfile.is_tarfile(backup_path), f"File {backup_path} is not a valid tar archive."

    with tarfile.open(backup_path, "r:gz") as tar:
        members = tar.getmembers()
        names = tar.getnames()
        assert any("netmon_config" in name for name in names), "Tarball does not contain 'netmon_config'."

        normalized = []
        for member in members:
            name = member.name
            assert not name.startswith("/"), f"Archive contains absolute path {name!r}."
            parts = tuple(p for p in name.split("/") if p not in ("", "."))
            assert ".." not in parts, f"Archive contains path traversal in {name!r}."
            normalized.append((member, parts))

        roots = [
            parts for member, parts in normalized
            if member.isdir() and parts and parts[-1] == "netmon_config"
        ]
        assert roots, "Tarball does not contain the netmon_config directory as a directory entry."
        root = next((r for r in roots if all(parts[:len(r)] == r for _, parts in normalized)), None)
        assert root is not None, "Tarball contains entries outside the backed-up netmon_config directory."

        archived = {}
        for member, parts in normalized:
            rel_parts = parts[len(root):]
            rel = "/".join(rel_parts)
            assert rel not in archived, f"Duplicate archive member for {rel!r}."
            if member.isdir():
                archived[rel] = ("dir", None)
            elif member.isfile():
                extracted = tar.extractfile(member)
                assert extracted is not None
                archived[rel] = ("file", extracted.read())
            elif member.issym():
                archived[rel] = ("symlink", member.linkname)
            else:
                raise AssertionError(f"Unsupported archive member type for {member.name!r}.")

    source = "/home/user/netmon_config"
    assert os.path.isdir(source), f"Source configuration directory {source} does not exist."
    expected = {"": ("dir", None)}
    for current, dirs, files in os.walk(source, followlinks=False):
        for name in dirs + files:
            full = os.path.join(current, name)
            rel = os.path.relpath(full, source).replace(os.sep, "/")
            if os.path.islink(full):
                expected[rel] = ("symlink", os.readlink(full))
            elif os.path.isdir(full):
                expected[rel] = ("dir", None)
            elif os.path.isfile(full):
                with open(full, "rb") as f:
                    expected[rel] = ("file", f.read())
            else:
                raise AssertionError(f"Unsupported source entry type for {full!r}.")
    assert archived == expected, "backup.tar.gz is not an exact backup of /home/user/netmon_config/."


def active_directives(content):
    directives = []
    for raw in content.splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or line.startswith(";") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        directives.append((key.strip(), value.strip()))
    return directives


def test_systemd_service():
    service_path = "/home/user/.config/systemd/user/log-filter.service"
    assert os.path.exists(service_path), f"Systemd service file {service_path} does not exist."
    assert os.path.isfile(service_path), f"{service_path} is not a regular file."

    with open(service_path, "r") as f:
        content = f.read()

    assert "[Unit]" in content, f"{service_path} is missing [Unit] section."
    assert "[Service]" in content, f"{service_path} is missing [Service] section."
    assert "ExecStart=/home/user/log_classifier.sh" in content, f"{service_path} is missing correct ExecStart directive."

    directives = active_directives(content)
    assert ("Description", "Network Log Filter") in directives, (
        f"{service_path} must have Description=Network Log Filter."
    )
    exec_values = [value for key, value in directives if key == "ExecStart"]
    assert exec_values, f"{service_path} has no active ExecStart directive."
    valid_exec = False
    for value in exec_values:
        try:
            argv = shlex.split(value)
        except ValueError:
            continue
        if argv and argv[0] == "/home/user/log_classifier.sh" and "%f" in argv[1:]:
            valid_exec = True
    assert valid_exec, (
        f"ExecStart must run /home/user/log_classifier.sh with %f as the file argument."
    )


def test_bashrc_env_var():
    bashrc_path = "/home/user/.bashrc"
    assert os.path.exists(bashrc_path), f"{bashrc_path} does not exist."

    with open(bashrc_path, "r") as f:
        content = f.read()

    assert "export FILTER_STRICT=1" in content, f"'export FILTER_STRICT=1' not found in {bashrc_path}."
    nonempty_lines = [line.strip() for line in content.splitlines() if line.strip()]
    assert nonempty_lines and nonempty_lines[-1] == "export FILTER_STRICT=1", (
        f"export FILTER_STRICT=1 must be the last non-empty line of {bashrc_path}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
