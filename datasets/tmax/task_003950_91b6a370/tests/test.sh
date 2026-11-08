#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
from pathlib import Path

import pytest


def decode_archive(path):
    data = Path(path).read_bytes()
    assert len(data) >= 1 and (len(data) - 1) % 2 == 0, f"Malformed test archive: {path}"
    expanded = bytearray()
    for i in range(0, len(data) - 1, 2):
        expanded.extend([data[i + 1]] * data[i])
    assert sum(expanded) % 256 == data[-1], f"Invalid checksum in test fixture: {path}"
    return expanded.decode("iso-8859-1").encode("utf-8")


def test_cfg_files_created():
    """Verify that the correct .cfg files are created and the corrupted one is skipped."""
    expected_cfg_files = [
        "/home/user/configs/db/node1.cfg",
        "/home/user/configs/db/node2.cfg",
        "/home/user/configs/web/front.cfg",
    ]

    for cfg in expected_cfg_files:
        assert os.path.isfile(cfg), f"Expected file {cfg} was not created."


def test_cfg_file_contents_match_archives():
    """Verify every valid supplied archive was actually decoded in full."""
    pairs = [
        ("/home/user/configs/db/node1.bak", "/home/user/configs/db/node1.cfg"),
        ("/home/user/configs/db/node2.bak", "/home/user/configs/db/node2.cfg"),
        ("/home/user/configs/web/front.bak", "/home/user/configs/web/front.cfg"),
    ]
    for bak, cfg in pairs:
        assert Path(cfg).read_bytes() == decode_archive(bak), f"Decoded contents of {cfg} are incorrect."


def test_corrupt_cfg_skipped():
    """Verify that the corrupted .bak file was not extracted."""
    corrupted_cfg = "/home/user/configs/cache/redis.cfg"
    assert not os.path.exists(corrupted_cfg), f"Corrupted file {corrupted_cfg} should not have been extracted."


def test_tracked_changes_log_exists():
    """Verify that the tracked_changes.log file was created."""
    log_file = "/home/user/tracked_changes.log"
    assert os.path.isfile(log_file), f"Log file {log_file} is missing."


def test_tracked_changes_log_content():
    """Verify the contents of tracked_changes.log match the expected output exactly."""
    log_file = "/home/user/tracked_changes.log"

    expected_lines = [
        "front.cfg: £50_bonus_promo",
        "node1.cfg: schema_v5",
        "node2.cfg: schema_v5_replica"
    ]

    with open(log_file, "r", encoding="utf-8") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, (
        f"Contents of {log_file} do not match expected output.\n"
        f"Expected: {expected_lines}\n"
        f"Actual: {actual_lines}"
    )


def test_utf8_encoding():
    """Verify that the extracted front.cfg is properly UTF-8 encoded."""
    front_cfg = "/home/user/configs/web/front.cfg"
    if os.path.exists(front_cfg):
        try:
            with open(front_cfg, "r", encoding="utf-8") as f:
                content = f.read()
            assert "£50_bonus_promo" in content, "The £ symbol was not correctly converted to UTF-8 in front.cfg."
        except UnicodeDecodeError:
            pytest.fail(f"File {front_cfg} is not properly UTF-8 encoded.")


def make_archive(path, runs, valid=True):
    raw = bytearray()
    checksum = 0
    expanded = bytearray()
    for count, value in runs:
        raw.extend((count, value))
        expanded.extend([value] * count)
        checksum = (checksum + count * value) % 256
    raw.append(checksum if valid else (checksum + 1) % 256)
    Path(path).write_bytes(raw)
    return expanded.decode("iso-8859-1").encode("utf-8")


def exercise(executable, strategy, root):
    root.mkdir(parents=True)
    token = secrets.token_hex(8).encode("ascii")
    runs = [
        (1, ord("I")), (1, ord("D")), (1, ord("=")),
        (4, ord("A")), (1, ord("_")),
    ] + [(1, b) for b in token] + [
        (1, ord("\n")), (1, ord("N")), (1, ord("O")), (1, ord("T")),
        (1, ord("E")), (1, ord("=")), (3, 0xA3), (1, ord("\n")),
    ]
    good = root / "random_valid.bak"
    bad = root / "random_invalid.bak"
    good_cfg = root / "random_valid.cfg"
    bad_cfg = root / "random_invalid.cfg"
    expected = make_archive(good, runs, True)
    make_archive(bad, [(5, ord("Q")), (1, 0xE9), (1, ord("\n"))], False)

    try:
        if strategy == "one_arg":
            subprocess.run([executable, str(good)], cwd="/home/user", timeout=10,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
            subprocess.run([executable, str(bad)], cwd="/home/user", timeout=10,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
        elif strategy == "two_args":
            subprocess.run([executable, str(good), str(good_cfg)], cwd="/home/user", timeout=10,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
            subprocess.run([executable, str(bad), str(bad_cfg)], cwd="/home/user", timeout=10,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
        elif strategy == "directory":
            subprocess.run([executable, str(root)], cwd="/home/user", timeout=10,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
        else:
            subprocess.run([executable], cwd="/home/user", timeout=10,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    except (OSError, subprocess.TimeoutExpired):
        return False

    return good_cfg.is_file() and good_cfg.read_bytes() == expected and not bad_cfg.exists()


def test_cpp_decoder_on_unseen_rle_archives(tmp_path):
    """Compile and exercise the submitted C++ decoder on unpredictable valid and corrupt inputs."""
    sources = sorted(Path("/home/user").rglob("*.cpp"))
    assert sources, "No C++ decoder source file was found under /home/user."

    compile_errors = []
    for index, source in enumerate(sources):
        executable = tmp_path / f"decoder_{index}"
        result = subprocess.run(
            ["g++", "-std=c++17", "-O2", str(source), "-o", str(executable)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
        )
        if result.returncode != 0:
            compile_errors.append(f"{source}: {result.stderr[-500:]}")
            continue

        for strategy in ("one_arg", "two_args", "directory", "no_args"):
            case_root = Path("/home/user/configs") / f".verifier_{secrets.token_hex(8)}"
            try:
                if exercise(str(executable), strategy, case_root):
                    return
            finally:
                if case_root.exists():
                    import shutil
                    shutil.rmtree(case_root, ignore_errors=True)

    pytest.fail("No submitted C++ source produced correct UTF-8 output for a new RLE archive while rejecting a bad checksum. "
                + " ".join(compile_errors))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
