#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tarfile
from pathlib import Path

import pytest


def test_gcode_time_log():
    log_path = "/home/user/gcode_time.log"
    assert os.path.exists(log_path), f"Log file {log_path} does not exist."
    with open(log_path, "r", encoding="utf-8") as f:
        content = f.read().strip()
    assert content == "Total Print Time: 7700", f"Log file content is incorrect. Expected 'Total Print Time: 7700', got '{content}'."


def test_tarball_exists_and_contents():
    tar_path = "/home/user/safe_backup.tar.gz"
    assert os.path.exists(tar_path), f"Tarball {tar_path} does not exist."
    assert tarfile.is_tarfile(tar_path), f"File {tar_path} is not a valid tar archive."

    with tarfile.open(tar_path, "r:gz") as tar:
        members = tar.getnames()

        for member in members:
            assert "loop_link" not in member, f"Symlink loop_link should not be in the archive, found: {member}"
            assert "research_data" not in member, f"Nested research_data should not be in the archive, found: {member}"

        expected_files = [
            "experiment1/meta.txt",
            "experiment1/run.gcode",
            "experiment2/meta.txt",
            "experiment2/run.gcode"
        ]

        found_files = set()
        for member in members:
            for exp in expected_files:
                if member.endswith(exp):
                    found_files.add(exp)

        missing = set(expected_files) - found_files
        assert not missing, f"Missing expected files in tarball: {missing}"


def test_tarball_meta_files_utf8():
    tar_path = "/home/user/safe_backup.tar.gz"
    assert os.path.exists(tar_path), f"Tarball {tar_path} does not exist."

    with tarfile.open(tar_path, "r:gz") as tar:
        for member in tar.getmembers():
            if member.name.endswith("experiment1/meta.txt"):
                f = tar.extractfile(member)
                assert f is not None, "Could not extract experiment1/meta.txt"
                try:
                    content = f.read().decode("utf-8")
                except UnicodeDecodeError:
                    pytest.fail("experiment1/meta.txt is not valid UTF-8.")
                assert "°" in content, "Missing '°' in experiment1/meta.txt"
                assert "Ü" in content, "Missing 'Ü' in experiment1/meta.txt"
            elif member.name.endswith("experiment2/meta.txt"):
                f = tar.extractfile(member)
                assert f is not None, "Could not extract experiment2/meta.txt"
                try:
                    content = f.read().decode("utf-8")
                except UnicodeDecodeError:
                    pytest.fail("experiment2/meta.txt is not valid UTF-8.")
                assert "é" in content, "Missing 'é' in experiment2/meta.txt"


def _python_candidates():
    candidates = []
    excluded = {"/tmp/test_final_state.py"}
    for root in ("/home/user", "/tmp", "/root"):
        if not os.path.isdir(root):
            continue
        for current, dirs, files in os.walk(root, followlinks=False):
            dirs[:] = [
                d for d in dirs
                if not os.path.islink(os.path.join(current, d))
                and d not in {"research_data", ".cache", ".local", "__pycache__"}
            ]
            for filename in files:
                if not filename.endswith(".py"):
                    continue
                path = os.path.join(current, filename)
                if path in excluded or os.path.islink(path) or not os.path.isfile(path):
                    continue
                try:
                    if os.path.getsize(path) > 1024 * 1024:
                        continue
                    source = Path(path).read_text(encoding="utf-8", errors="ignore")
                except OSError:
                    continue
                if "research_data" in source and "safe_backup" in source and "gcode_time" in source:
                    candidates.append(path)
    return sorted(set(candidates), key=lambda p: os.path.getmtime(p), reverse=True)


def _source_snapshot(base):
    expected = {}
    total = 0
    marker = b"; PRINT_TIME: "
    for current, dirs, files in os.walk(base, followlinks=False):
        dirs[:] = sorted(
            d for d in dirs if not os.path.islink(os.path.join(current, d))
        )
        for filename in sorted(files):
            path = os.path.join(current, filename)
            if os.path.islink(path) or not os.path.isfile(path):
                continue
            relative = os.path.relpath(path, base).replace(os.sep, "/")
            raw = Path(path).read_bytes()
            if relative.endswith(".txt"):
                expected[relative] = raw.decode("iso-8859-1").encode("utf-8")
            else:
                expected[relative] = raw
            if relative.endswith(".gcode"):
                for line in raw.splitlines():
                    if line.startswith(marker):
                        total += int(line[len(marker):].decode("ascii"))
    return expected, total


def _outputs_match(expected, total):
    tar_path = "/home/user/safe_backup.tar.gz"
    log_path = "/home/user/gcode_time.log"
    try:
        if Path(log_path).read_text(encoding="utf-8").strip() != f"Total Print Time: {total}":
            return False
        if not tarfile.is_tarfile(tar_path):
            return False
        found = {}
        with tarfile.open(tar_path, "r:gz") as tar:
            for member in tar.getmembers():
                name = member.name
                if name.startswith("./"):
                    name = name[2:]
                if name.startswith("/") or ".." in Path(name).parts:
                    return False
                if member.issym() or member.islnk():
                    return False
                if member.isdir():
                    continue
                if not member.isfile() or name in found:
                    return False
                extracted = tar.extractfile(member)
                if extracted is None:
                    return False
                found[name] = extracted.read()
        return found == expected
    except (OSError, UnicodeError, tarfile.TarError, ValueError):
        return False


def test_zz_script_is_executed_and_processes_dynamic_dataset():
    base = "/home/user/research_data"
    token = secrets.token_hex(8)
    challenge_dir = os.path.join(base, "verification_" + token)
    os.makedirs(os.path.join(challenge_dir, "nested"))

    print_time = secrets.randbelow(8000) + 1001
    Path(os.path.join(challenge_dir, "details.txt")).write_bytes(
        "Données dynamiques: façade, piñata, 198°C.\n".encode("iso-8859-1")
    )
    Path(os.path.join(challenge_dir, "nested", "job.gcode")).write_bytes(
        f"G28\n; PRINT_TIME: {print_time}\nM104 S0\n".encode("ascii")
    )
    payload = secrets.token_bytes(73)
    Path(os.path.join(challenge_dir, "nested", "payload.bin")).write_bytes(payload)
    os.symlink("/etc/passwd", os.path.join(challenge_dir, "forbidden_file_link"))
    os.symlink(base, os.path.join(challenge_dir, "forbidden_directory_link"))

    expected, total = _source_snapshot(base)
    candidates = _python_candidates()
    assert candidates, "No persistent Python backup script was found."

    successful = None
    errors = []
    for candidate in candidates:
        for output in ("/home/user/safe_backup.tar.gz", "/home/user/gcode_time.log"):
            try:
                os.remove(output)
            except FileNotFoundError:
                pass
        try:
            result = subprocess.run(
                ["python3", candidate],
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=30,
                check=False,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            errors.append(f"{candidate}: {exc}")
            continue
        if result.returncode == 0 and _outputs_match(expected, total):
            successful = candidate
            break
        errors.append(f"{candidate}: exit status {result.returncode}")

    assert successful is not None, (
        "No Python script regenerated correct outputs from the dynamically extended "
        f"dataset. Candidates/errors: {errors}"
    )

    assert _outputs_match(expected, total), "Regenerated archive or log is incorrect."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
