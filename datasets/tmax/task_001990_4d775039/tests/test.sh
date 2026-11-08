#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

CONFIG_DIR = Path("/home/user/configs")
REPORT = Path("/home/user/drift_report.csv")
ORIGINAL_EXPECTED = (
    "Month,Previous_Month,Distance\n"
    "2023-02,2023-01,0.600\n"
    "2023-03,2023-02,0.800"
)


def read_config(path):
    data = path.read_bytes()
    if data.startswith((b"\xff\xfe", b"\xfe\xff")):
        return data.decode("utf-16")
    return data.decode("utf-8-sig")


def derive_expected(config_dir):
    monthly_keys = {}
    for path in config_dir.glob("*.ini"):
        match = re.fullmatch(r"backup_(\d{4}-\d{2})-\d{2}\.ini", path.name)
        if not match:
            continue
        month = match.group(1)
        keys = monthly_keys.setdefault(month, set())
        in_security = False
        for raw_line in read_config(path).splitlines():
            line = raw_line.strip()
            if not line or line.startswith(("#", ";")):
                continue
            if line.startswith("[") and line.endswith("]"):
                in_security = line[1:-1].strip() == "Security"
                continue
            if in_security:
                delimiter_positions = [p for p in (line.find("="), line.find(":")) if p >= 0]
                if delimiter_positions:
                    key = line[:min(delimiter_positions)].strip()
                    if key:
                        keys.add(key)

    months = sorted(monthly_keys)
    rows = ["Month,Previous_Month,Distance"]
    for previous, current in zip(months, months[1:]):
        previous_keys = monthly_keys[previous]
        current_keys = monthly_keys[current]
        union = previous_keys | current_keys
        distance = 0.0 if not union else 1.0 - len(previous_keys & current_keys) / len(union)
        rows.append(f"{current},{previous},{distance:.3f}")
    return "\n".join(rows)


def install_dynamic_fixture():
    shutil.rmtree(CONFIG_DIR)
    CONFIG_DIR.mkdir(parents=True)
    files = [
        ("backup_2041-07-02.ini", "utf-8", "[General]\nalpha=decoy\n[Security]\nalpha=1\nbeta=2\n[Other]\ndecoy=1\n"),
        ("backup_2041-07-23.ini", "utf-16", "[Security]\nbeta=x\ngamma=y\n"),
        ("backup_2041-08-04.ini", "utf-16", "[Network]\nport=80\n[Security]\nbeta=1\ndelta=2\n[Ignored]\ngamma=not_security\n"),
        ("backup_2041-08-19.ini", "utf-8", "[Security]\nepsilon=3\n"),
        ("backup_2041-10-11.ini", "utf-8", "[Security]\ndelta=1\nepsilon=2\nzeta=3\n"),
        ("backup_2041-11-09.ini", "utf-16", "[Security]\nzeta=1\neta=2\ntheta=3\n[Other]\ndelta=decoy\n"),
    ]
    for name, encoding, content in files:
        (CONFIG_DIR / name).write_text(content, encoding=encoding)


def restore_configs(source):
    if CONFIG_DIR.exists():
        shutil.rmtree(CONFIG_DIR)
    shutil.copytree(source, CONFIG_DIR)


def run_script(script):
    if REPORT.exists():
        REPORT.unlink()
    return subprocess.run(
        ["python3", str(script)],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )


def report_text():
    if not REPORT.is_file():
        return None
    return REPORT.read_text(encoding="utf-8").strip()


def test_python_script_exists_runs_and_handles_unseen_inputs():
    candidates = sorted(
        path for path in Path("/home/user").rglob("*.py")
        if CONFIG_DIR not in path.parents and path.is_file() and not path.is_symlink()
    )
    assert candidates, "No Python script was written under /home/user."

    backup_parent = Path(tempfile.mkdtemp(prefix="drift-verifier-"))
    original_configs = backup_parent / "configs"
    shutil.copytree(CONFIG_DIR, original_configs)
    winner = None
    diagnostics = []

    try:
        for script in candidates:
            restore_configs(original_configs)
            try:
                result = run_script(script)
            except subprocess.TimeoutExpired:
                diagnostics.append(f"{script}: timed out on the original inputs")
                continue
            if result.returncode != 0 or report_text() != ORIGINAL_EXPECTED:
                diagnostics.append(f"{script}: did not produce the required original report")
                continue

            install_dynamic_fixture()
            dynamic_expected = derive_expected(CONFIG_DIR)
            try:
                result = run_script(script)
            except subprocess.TimeoutExpired:
                diagnostics.append(f"{script}: timed out on unseen inputs")
                continue
            if result.returncode == 0 and report_text() == dynamic_expected:
                winner = script
                break
            diagnostics.append(f"{script}: failed recomputed unseen-input results")
    finally:
        restore_configs(original_configs)
        shutil.rmtree(backup_parent, ignore_errors=True)

    assert winner is not None, (
        "No submitted Python script correctly recomputed configuration drift on both "
        "the supplied and unseen mixed-encoding inputs. " + "; ".join(diagnostics)
    )

    result = run_script(winner)
    assert result.returncode == 0, (
        f"The validated script failed when rerun on the supplied inputs. stderr: {result.stderr}"
    )


def test_drift_report_exists():
    assert os.path.isfile("/home/user/drift_report.csv"), "The file /home/user/drift_report.csv does not exist."


def test_drift_report_content():
    expected_content = (
        "Month,Previous_Month,Distance\n"
        "2023-02,2023-01,0.600\n"
        "2023-03,2023-02,0.800"
    ).strip()

    with open("/home/user/drift_report.csv", "r", encoding="utf-8") as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, (
        f"The content of /home/user/drift_report.csv does not match the expected output.\n"
        f"Expected:\n{expected_content}\n\n"
        f"Actual:\n{actual_content}"
    )


def test_drift_report_lines():
    with open("/home/user/drift_report.csv", "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 3, f"Expected 3 lines in the CSV (1 header, 2 data rows), but found {len(lines)}."
    assert lines[0] == "Month,Previous_Month,Distance", f"Header is incorrect. Found: {lines[0]}"

    row1 = lines[1].split(',')
    assert len(row1) == 3, "Row 1 does not have exactly 3 columns."
    assert row1[0] == "2023-02", f"Row 1 Month should be 2023-02, found {row1[0]}"
    assert row1[1] == "2023-01", f"Row 1 Previous_Month should be 2023-01, found {row1[1]}"
    assert row1[2] == "0.600", f"Row 1 Distance should be 0.600, found {row1[2]}"

    row2 = lines[2].split(',')
    assert len(row2) == 3, "Row 2 does not have exactly 3 columns."
    assert row2[0] == "2023-03", f"Row 2 Month should be 2023-03, found {row2[0]}"
    assert row2[1] == "2023-02", f"Row 2 Previous_Month should be 2023-02, found {row2[1]}"
    assert row2[2] == "0.800", f"Row 2 Distance should be 0.800, found {row2[2]}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
