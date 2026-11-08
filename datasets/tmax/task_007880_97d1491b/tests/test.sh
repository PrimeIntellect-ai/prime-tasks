#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import shutil
import subprocess
import uuid
from collections import defaultdict
from pathlib import Path

HOME = Path("/home/user")
ACCESS = HOME / "access_logs.csv"
EMPLOYEES = HOME / "employees.csv"
SUSPECTS = HOME / "suspects.csv"


def validate_suspects_csv():
    assert os.path.exists(SUSPECTS), f"Output file {SUSPECTS} does not exist."
    assert os.path.isfile(SUSPECTS), f"{SUSPECTS} is not a file."

    error_counts = defaultdict(int)
    with open(ACCESS, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row.get("status_code") == "403":
                error_counts[row.get("emp_id")] += 1

    suspect_ids = {
        emp_id: count for emp_id, count in error_counts.items() if count > 3
    }

    emp_emails = {}
    with open(EMPLOYEES, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            emp_emails[row.get("emp_id")] = row.get("email")

    expected_rows = []
    for emp_id, count in suspect_ids.items():
        email = emp_emails.get(emp_id, "")
        if "@" in email:
            local, domain = email.split("@", 1)
            if len(local) > 0:
                masked_local = local[0] + "*" * (len(local) - 1)
            else:
                masked_local = local
            masked_email = f"{masked_local}@{domain}"
        else:
            masked_email = email

        expected_rows.append({
            "emp_id": emp_id,
            "masked_email": masked_email,
            "error_count": str(count),
        })

    expected_rows.sort(key=lambda x: x["emp_id"])

    with open(SUSPECTS, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            header = []

        assert header == ["emp_id", "masked_email", "error_count"], \
            f"Header in {SUSPECTS} is incorrect. Got: {header}"

        actual_rows = []
        for row in reader:
            if not row:
                continue
            assert len(row) == 3, \
                f"Row in {SUSPECTS} does not have exactly 3 columns: {row}"
            actual_rows.append({
                "emp_id": row[0],
                "masked_email": row[1],
                "error_count": row[2],
            })

    assert len(actual_rows) == len(expected_rows), \
        f"Expected {len(expected_rows)} rows in {SUSPECTS}, but got {len(actual_rows)}."

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, \
            f"Row {i + 1} mismatch. Expected: {expected}, Got: {actual}"


def is_elf_executable(path):
    try:
        return path.is_file() and os.access(path, os.X_OK) and path.read_bytes()[:4] == b"\x7fELF"
    except OSError:
        return False


def compile_rust_candidates():
    commands = []
    diagnostics = []
    manifests = sorted(
        (p for p in HOME.rglob("Cargo.toml") if "target" not in p.parts),
        key=lambda p: (p != HOME / "log_analyzer" / "Cargo.toml", str(p)),
    )

    for index, manifest in enumerate(manifests):
        target_dir = Path(f"/tmp/verifier-cargo-target-{index}")
        shutil.rmtree(target_dir, ignore_errors=True)
        env = os.environ.copy()
        env["CARGO_TARGET_DIR"] = str(target_dir)
        env.pop("RUSTC_WRAPPER", None)
        env.pop("RUSTC_WORKSPACE_WRAPPER", None)
        try:
            result = subprocess.run(
                ["cargo", "build", "--quiet", "--manifest-path", str(manifest), "--bins"],
                cwd=HOME,
                env=env,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=180,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            diagnostics.append(f"cargo build failed for {manifest}: {exc}")
            continue
        if result.returncode != 0:
            diagnostics.append(f"cargo build returned {result.returncode} for {manifest}")
            continue

        debug_dir = target_dir / "debug"
        if debug_dir.is_dir():
            for artifact in sorted(debug_dir.iterdir()):
                if is_elf_executable(artifact):
                    commands.append(([str(artifact)], f"Cargo project {manifest}"))

    rust_sources = sorted(
        p for p in HOME.rglob("*.rs")
        if "target" not in p.parts and ".cargo" not in p.parts
    )
    for index, source in enumerate(rust_sources):
        binary = Path(f"/tmp/verifier-rust-bin-{index}")
        try:
            result = subprocess.run(
                ["rustc", "--edition=2021", str(source), "-o", str(binary)],
                cwd=HOME,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=120,
            )
        except (OSError, subprocess.TimeoutExpired):
            continue
        if result.returncode == 0 and is_elf_executable(binary):
            commands.append(([str(binary)], f"Rust source {source}"))

    return commands, diagnostics


def run_candidate(command):
    try:
        result = subprocess.run(
            command,
            cwd=HOME,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=60,
        )
        return result.returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def make_fixture():
    token = uuid.uuid4().hex[:10]
    ids = ["E" + token[:4].upper(), "E" + token[4:8].upper(), "E" + token[2:6].upper()]
    if len(set(ids)) != 3:
        ids = ["E901", "E117", "E640"]

    access_lines = ["timestamp,ip_address,emp_id,status_code,endpoint"]
    counts = {ids[0]: 5, ids[1]: 3, ids[2]: 4}
    minute = 0
    for emp_id, count in counts.items():
        for _ in range(count):
            access_lines.append(
                f"2026-01-02T09:{minute:02d},10.20.30.{minute + 1},{emp_id},403,/private"
            )
            minute += 1
        access_lines.append(
            f"2026-01-02T09:{minute:02d},10.20.30.{minute + 1},{emp_id},200,/public"
        )
        minute += 1

    employee_lines = [
        "emp_id,full_name,email,department",
        f"{ids[0]},Test Alpha,a{token}@dynamic.example,Engineering",
        f"{ids[1]},Test Beta,beta{token[:4]}@internal.test,HR",
        f"{ids[2]},Test Gamma,g{token[:7]}@audit.invalid,Sales",
    ]
    return ("\n".join(access_lines) + "\n").encode(), ("\n".join(employee_lines) + "\n").encode()


def test_rust_program_generates_correct_csv():
    original_access = ACCESS.read_bytes()
    original_employees = EMPLOYEES.read_bytes()
    original_suspects = SUSPECTS.read_bytes() if SUSPECTS.is_file() else None
    completed = False

    try:
        commands, diagnostics = compile_rust_candidates()
        assert commands, "No compilable Rust executable was found. " + "; ".join(diagnostics)

        fixture_access, fixture_employees = make_fixture()
        selected = None
        failures = []

        for command, description in commands:
            ACCESS.write_bytes(fixture_access)
            EMPLOYEES.write_bytes(fixture_employees)
            if SUSPECTS.exists():
                SUSPECTS.unlink()

            if not run_candidate(command):
                failures.append(f"{description} did not execute successfully")
                continue
            if ACCESS.read_bytes() != fixture_access or EMPLOYEES.read_bytes() != fixture_employees:
                failures.append(f"{description} modified an input CSV")
                continue
            try:
                validate_suspects_csv()
            except Exception as exc:
                failures.append(f"{description} produced incorrect dynamic output: {exc}")
                continue
            selected = (command, description)
            break

        assert selected is not None, \
            "No compiled Rust program processed the dynamic input correctly. " + "; ".join(failures)

        ACCESS.write_bytes(original_access)
        EMPLOYEES.write_bytes(original_employees)
        if SUSPECTS.exists():
            SUSPECTS.unlink()

        command, description = selected
        assert run_candidate(command), f"{description} failed on the supplied input files"
        assert ACCESS.read_bytes() == original_access, f"{description} modified {ACCESS}"
        assert EMPLOYEES.read_bytes() == original_employees, f"{description} modified {EMPLOYEES}"

        validate_suspects_csv()
        completed = True
    finally:
        ACCESS.write_bytes(original_access)
        EMPLOYEES.write_bytes(original_employees)
        if not completed:
            if original_suspects is None:
                if SUSPECTS.exists():
                    SUSPECTS.unlink()
            else:
                SUSPECTS.write_bytes(original_suspects)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
