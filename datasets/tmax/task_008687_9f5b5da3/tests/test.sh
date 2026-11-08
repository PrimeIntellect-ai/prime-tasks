#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pytest

def test_report_file_exists():
    """Check that the output report file has been created."""
    file_path = "/home/user/report.txt"
    assert os.path.isfile(file_path), f"Expected output file {file_path} does not exist."

def test_report_file_contents():
    """Check that the output report has the correct format and calculations."""
    file_path = "/home/user/report.txt"

    expected_contents = (
        "Sensor S1:\n"
        "- Max 3-Period SMA: 58.00\n"
        "- Final 3-Period SMA: 53.00\n"
        "\n"
        "Sensor S2:\n"
        "- Max 3-Period SMA: 22.67\n"
        "- Final 3-Period SMA: 22.67\n"
    )

    with open(file_path, "r", encoding="utf-8") as f:
        actual_contents = f.read()

    assert actual_contents.strip() == expected_contents.strip(), (
        f"Contents of {file_path} do not match the expected report.\n"
        f"Expected:\n{expected_contents}\n"
        f"Got:\n{actual_contents}"
    )

    assert actual_contents.endswith("\n\n") or actual_contents.endswith("22.67\n\n") or "\n\nSensor S2" in actual_contents, \
        "Ensure there is a blank line after each sensor block as requested."
TEST_EOF

cat << 'DYNAMIC_EOF' > /tmp/test_rust_etl.py
import csv
import json
import os
from pathlib import Path
import random
import secrets
import shutil
import subprocess

HOME = Path("/home/user")
CSV_PATH = HOME / "sensor_data.csv"
REPORT_PATH = HOME / "report.txt"


def expected_report(csv_text):
    grouped = {}
    rows = csv.DictReader(csv_text.splitlines())
    for row in rows:
        key = (row["sensor_id"], int(row["timestamp"]))
        grouped.setdefault(key, []).append(float(row["value"]))

    by_sensor = {}
    for (sensor, timestamp), values in grouped.items():
        by_sensor.setdefault(sensor, []).append((timestamp, sum(values) / len(values)))

    blocks = []
    for sensor in sorted(by_sensor):
        points = sorted(by_sensor[sensor])
        moving = []
        deduped_values = [value for _, value in points]
        for index in range(len(deduped_values)):
            window = deduped_values[max(0, index - 2):index + 1]
            moving.append(sum(window) / len(window))
        blocks.append(
            f"Sensor {sensor}:\n"
            f"- Max 3-Period SMA: {max(moving):.2f}\n"
            f"- Final 3-Period SMA: {moving[-1]:.2f}\n\n"
        )
    return "".join(blocks)


def make_fixture(case_number):
    token = secrets.token_hex(4).upper()
    names = [f"A{token}", f"M{token}", f"Z{token}"]
    offset = secrets.randbelow(7) + case_number
    base = 1200 + secrets.randbelow(500)
    desired = {
        names[0]: [40 + offset, 70 + offset, 80 + offset, 10 + offset, 5 + offset],
        names[1]: [-5 - offset, -15 - offset, -25 - offset, -35 - offset],
        names[2]: [20 + offset, 30 + offset],
    }

    lines = []
    for sensor_index, sensor in enumerate(names):
        for index, value in enumerate(desired[sensor]):
            timestamp = base + sensor_index * 100 + index * 7
            if (index + sensor_index + case_number) % 2 == 0:
                lines.append(f"{timestamp},{sensor},{value - 2}.0")
                lines.append(f"{timestamp},{sensor},{value + 2}.0")
            else:
                lines.append(f"{timestamp},{sensor},{value}.0")

    random.SystemRandom().shuffle(lines)
    return "timestamp,sensor_id,value\n" + "\n".join(lines) + "\n"


def discover_commands():
    manifests = []
    rust_sources = []
    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if d not in {"target", ".cargo", ".git"}]
        root_path = Path(root)
        if "Cargo.toml" in files:
            manifests.append(root_path / "Cargo.toml")
        for filename in files:
            if filename.endswith(".rs"):
                rust_sources.append(root_path / filename)

    assert rust_sources, "No Rust source file was found under /home/user."
    commands = []

    for manifest in sorted(manifests, key=lambda p: (len(p.parts), str(p))):
        try:
            metadata = subprocess.run(
                ["cargo", "metadata", "--no-deps", "--format-version", "1", "--manifest-path", str(manifest)],
                cwd=manifest.parent,
                text=True,
                capture_output=True,
                timeout=30,
                check=True,
            )
            document = json.loads(metadata.stdout)
            package_ids = {
                package["id"] for package in document.get("packages", [])
                if Path(package["manifest_path"]).resolve() == manifest.resolve()
            }
            bins = []
            for package in document.get("packages", []):
                if package.get("id") in package_ids:
                    for target in package.get("targets", []):
                        if "bin" in target.get("kind", []):
                            bins.append(target["name"])
            if bins:
                for binary_name in bins:
                    commands.append((
                        f"Cargo binary {binary_name} from {manifest}",
                        ["cargo", "run", "--quiet", "--manifest-path", str(manifest), "--bin", binary_name],
                        manifest.parent,
                    ))
            else:
                commands.append((
                    f"Cargo project {manifest}",
                    ["cargo", "run", "--quiet", "--manifest-path", str(manifest)],
                    manifest.parent,
                ))
        except Exception:
            commands.append((
                f"Cargo project {manifest}",
                ["cargo", "run", "--quiet", "--manifest-path", str(manifest)],
                manifest.parent,
            ))

    for index, source in enumerate(sorted(rust_sources)):
        try:
            text = source.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        if "fn main" not in text:
            continue
        binary = Path(f"/tmp/verifier_rust_etl_{index}")
        compiled = subprocess.run(
            ["rustc", str(source), "-o", str(binary)],
            cwd=source.parent,
            text=True,
            capture_output=True,
            timeout=90,
        )
        if compiled.returncode == 0:
            commands.append((f"standalone Rust source {source}", [str(binary)], source.parent))

    assert commands, "Rust source exists, but no executable Rust program could be identified."
    return commands


def test_rust_program_recomputes_report_for_new_inputs():
    original_csv = CSV_PATH.read_bytes()
    original_report = REPORT_PATH.read_bytes() if REPORT_PATH.is_file() else None
    fixtures = [make_fixture(1), make_fixture(2)]
    commands = discover_commands()
    failures = []

    try:
        for label, command, cwd in commands:
            passed = True
            details = []
            for fixture in fixtures:
                CSV_PATH.write_text(fixture, encoding="utf-8")
                if REPORT_PATH.exists():
                    if REPORT_PATH.is_file() or REPORT_PATH.is_symlink():
                        REPORT_PATH.unlink()
                    else:
                        shutil.rmtree(REPORT_PATH)
                try:
                    result = subprocess.run(
                        command,
                        cwd=cwd,
                        text=True,
                        capture_output=True,
                        timeout=120,
                    )
                except Exception as exc:
                    passed = False
                    details.append(str(exc))
                    break
                expected = expected_report(fixture)
                actual = REPORT_PATH.read_text(encoding="utf-8") if REPORT_PATH.is_file() else None
                if result.returncode != 0 or actual != expected:
                    passed = False
                    details.append(
                        f"exit={result.returncode}, stdout={result.stdout!r}, "
                        f"stderr={result.stderr!r}, expected={expected!r}, actual={actual!r}"
                    )
                    break
            if passed:
                return
            failures.append(f"{label}: {'; '.join(details)}")

        raise AssertionError(
            "No submitted Rust program regenerated the exact report for changed CSV inputs.\n"
            + "\n".join(failures)
        )
    finally:
        CSV_PATH.write_bytes(original_csv)
        if original_report is None:
            if REPORT_PATH.exists() and (REPORT_PATH.is_file() or REPORT_PATH.is_symlink()):
                REPORT_PATH.unlink()
        else:
            REPORT_PATH.write_bytes(original_report)
DYNAMIC_EOF

ok=1
if ! python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    ok=0
fi
if [ "$ok" -eq 1 ]; then
    if ! python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_rust_etl.py -x --tb=short 2>&1; then
        ok=0
    fi
fi

echo "$ok" > /logs/verifier/reward.txt
