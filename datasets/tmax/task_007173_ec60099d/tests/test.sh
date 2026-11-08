#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pytest

def test_processed_log_1_skipped():
    """Ensure the file already in the manifest is skipped and not processed."""
    path = "/home/user/processed_logs/log_20231001_N01.csv"
    assert not os.path.exists(path), f"File {path} should not exist because it was already in the manifest."

def test_processed_log_2_exists_and_content():
    """Ensure the second log is processed correctly, encoded in UTF-8, and filtered."""
    path = "/home/user/processed_logs/log_20231002_N02.csv"
    assert os.path.isfile(path), f"File {path} does not exist."

    try:
        with open(path, "r", encoding="utf-8") as f:
            lines = [line.strip() for line in f if line.strip()]
    except UnicodeDecodeError:
        pytest.fail(f"File {path} is not correctly encoded in UTF-8.")

    expected_lines = [
        "id,timestamp,status,message",
        "2,00:05,FAILED,Conexión falló en el servidor",
        "4,00:15,ERROR,Falló la operación"
    ]

    assert lines == expected_lines, f"Content of {path} does not match expected filtered output."

def test_processed_log_3_exists_and_content():
    """Ensure the third log is processed correctly, encoded in UTF-8, and filtered."""
    path = "/home/user/processed_logs/log_20231003_N03.csv"
    assert os.path.isfile(path), f"File {path} does not exist."

    try:
        with open(path, "r", encoding="utf-8") as f:
            lines = [line.strip() for line in f if line.strip()]
    except UnicodeDecodeError:
        pytest.fail(f"File {path} is not correctly encoded in UTF-8.")

    expected_lines = [
        "id,timestamp,status,message",
        "1,00:01,FAILED,Network timeout"
    ]

    assert lines == expected_lines, f"Content of {path} does not match expected filtered output."

def test_manifest_updated_correctly():
    """Ensure the manifest contains all the required files."""
    path = "/home/user/processed_manifest.txt"
    assert os.path.isfile(path), f"Manifest file {path} does not exist."

    with open(path, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_entries = {
        "log_20231001_N01.csv",
        "log_20231002_N02.csv",
        "log_20231003_N03.csv"
    }

    assert set(lines) == expected_entries, f"Manifest file content is incorrect. Expected entries: {expected_entries}, got: {set(lines)}"
    assert lines[0] == "log_20231001_N01.csv", "The first entry in the manifest should remain 'log_20231001_N01.csv'."
    assert len(lines) == 3, f"Manifest file should contain exactly 3 entries, but has {len(lines)}."
TEST_EOF

cat << 'TEST_EOF' > /tmp/test_incremental_behavior.py
import os
import subprocess
import time
import uuid
from pathlib import Path

RAW = Path("/home/user/raw_logs")
OUT = Path("/home/user/processed_logs")
MANIFEST = Path("/home/user/processed_manifest.txt")
EXCLUDED = {Path("/tmp/test_final_state.py"), Path("/tmp/test_incremental_behavior.py")}


def find_python_scripts():
    candidates = []
    roots = [Path("/home/user"), Path("/root"), Path("/tmp"), Path("/workspace"), Path("/app"), Path("/opt")]
    ignored_parts = {"raw_logs", "processed_logs", ".cache", ".git", "site-packages", "__pycache__"}

    for root in roots:
        if not root.exists():
            continue
        for directory, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d not in ignored_parts]
            for filename in filenames:
                path = Path(directory) / filename
                if path in EXCLUDED or not path.is_file():
                    continue
                try:
                    if path.stat().st_size > 1_000_000:
                        continue
                    prefix = path.read_bytes()[:4096]
                except OSError:
                    continue

                is_py = path.suffix == ".py"
                has_python_shebang = prefix.startswith(b"#!") and b"python" in prefix.splitlines()[0].lower()
                mentions_task = b"raw_logs" in prefix and b"processed_manifest" in prefix

                if root == Path("/home/user"):
                    if is_py or has_python_shebang:
                        candidates.append(path)
                elif (is_py or has_python_shebang) and mentions_task:
                    candidates.append(path)

    return sorted(set(candidates), key=lambda p: p.stat().st_mtime_ns, reverse=True)


def manifest_lines():
    return [line.strip() for line in MANIFEST.read_text(encoding="utf-8").splitlines() if line.strip()]


def filtered_lines(path):
    text = path.read_bytes().decode("utf-8")
    return [line.strip() for line in text.splitlines() if line.strip()]


def test_script_executes_on_new_inputs_and_is_incremental():
    scripts = find_python_scripts()
    assert scripts, "No Python processing script was found."

    baseline_manifest = MANIFEST.read_bytes()
    baseline_lines = manifest_lines()
    successful = None
    successful_state = None
    errors = []

    for script in scripts:
        token = uuid.uuid4().hex[:10].upper()
        day = 10 + (int(token[0], 16) % 10)
        date_hyphen = f"2037-08-{day:02d}"
        date_compact = f"203708{day:02d}"
        node = f"Q{token}"
        skip_node = f"S{token}"

        source = RAW / f"System Log - {date_hyphen} - {node}.csv"
        target_name = f"log_{date_compact}_{node}.csv"
        target = OUT / target_name
        skip_source = RAW / f"System Log - {date_hyphen} - {skip_node}.csv"
        skip_name = f"log_{date_compact}_{skip_node}.csv"
        skip_target = OUT / skip_name

        source_text = (
            "   # randomized comment that must disappear\n"
            "id,timestamp,status,message\n"
            "1,11:01,SUCCESS,Operación normal\n"
            "2,11:02,FAILED,Conexión perdida ñ\n"
            "3,11:03,ERROR,Disco inválido á\n"
            "4,11:04,SUCCESS,Another discarded event\n"
        )
        skip_text = (
            "id,timestamp,status,message\n"
            "9,22:00,FAILED,This pre-manifested file must be skipped\n"
        )
        source.write_bytes(source_text.encode("iso-8859-1"))
        skip_source.write_bytes(skip_text.encode("iso-8859-1"))
        MANIFEST.write_text(
            baseline_manifest.decode("utf-8").rstrip("\n") + "\n" + skip_name + "\n",
            encoding="utf-8",
        )
        target.unlink(missing_ok=True)
        skip_target.unlink(missing_ok=True)

        try:
            result = subprocess.run(
                ["python3", str(script)],
                cwd=str(script.parent),
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=20,
            )
            expected = [
                "id,timestamp,status,message",
                "2,11:02,FAILED,Conexión perdida ñ",
                "3,11:03,ERROR,Disco inválido á",
            ]
            lines = manifest_lines() if MANIFEST.exists() else []
            worked = (
                result.returncode == 0
                and target.is_file()
                and not skip_target.exists()
                and filtered_lines(target) == expected
                and lines[:len(baseline_lines)] == baseline_lines
                and lines[len(baseline_lines):] == [skip_name, target_name]
                and lines.count(target_name) == 1
                and lines.count(skip_name) == 1
            )
        except Exception as exc:
            worked = False
            result = None
            errors.append(f"{script}: {exc}")

        if worked:
            successful = script
            successful_state = (target, target_name, skip_target, skip_name, source, skip_source)
            break

        if result is not None:
            errors.append(f"{script}: exit={result.returncode}, stderr={result.stderr[-300:]}")
        MANIFEST.write_bytes(baseline_manifest)
        for path in (source, target, skip_source, skip_target):
            path.unlink(missing_ok=True)

    assert successful is not None, "No submitted Python script correctly processed randomized new inputs. " + " | ".join(errors)

    target, target_name, skip_target, skip_name, source, skip_source = successful_state
    before_bytes = target.read_bytes()
    before_mtime = target.stat().st_mtime_ns
    before_manifest = MANIFEST.read_bytes()

    time.sleep(1.05)
    rerun = subprocess.run(
        ["python3", str(successful)],
        cwd=str(successful.parent),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert rerun.returncode == 0, f"The processing script failed on its incremental rerun: {rerun.stderr}"
    assert target.read_bytes() == before_bytes, "An already-manifested output was changed on rerun."
    assert target.stat().st_mtime_ns == before_mtime, "An already-manifested output was rewritten on rerun."
    assert MANIFEST.read_bytes() == before_manifest, "The manifest changed or gained duplicates on rerun."
    assert not skip_target.exists(), "A source whose target was already in the manifest was processed."
    assert manifest_lines().count(target_name) == 1
    assert manifest_lines().count(skip_name) == 1
TEST_EOF

ok=1
python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 || ok=0
if [ "$ok" -eq 1 ]; then
    python3 -m pytest /tmp/test_incremental_behavior.py -x --tb=short 2>&1 || ok=0
fi

echo "$ok" > /logs/verifier/reward.txt
