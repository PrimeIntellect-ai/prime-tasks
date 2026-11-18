#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import shutil
import stat
import subprocess
import tempfile
from pathlib import Path

import pytest

PIPELINE_DIR = Path("/home/user/pipeline")
SRC_DIR = PIPELINE_DIR / "src"
RECOVERED_DAT = PIPELINE_DIR / "recovered.dat"
POISON_TXT = Path("/home/user/poison.txt")
BUILD_FLAG = PIPELINE_DIR / "build_success.flag"
AGGREGATE_AWK = PIPELINE_DIR / "aggregate.awk"
METRICS_TXT = PIPELINE_DIR / "metrics.txt"
COMPILE_SH = PIPELINE_DIR / "compile.sh"
BUILD_SH = PIPELINE_DIR / "build.sh"


def test_phase1_recovered_dat():
    assert RECOVERED_DAT.is_file(), f"Phase 1 failed: {RECOVERED_DAT} is missing."

    content = RECOVERED_DAT.read_text().strip()
    expected_lines = [
        "SET config_path /etc/default",
        "SET max_workers 4",
        "SET retries 5",
        "SET feature_flag true",
    ]
    expected_content = "\n".join(expected_lines)
    assert content == expected_content, (
        f"Phase 1 failed: {RECOVERED_DAT} does not contain the exact expected valid transactions."
    )


def _candidate_delta_scripts():
    excluded = {COMPILE_SH.resolve(), BUILD_SH.resolve()}
    candidates = []
    for path in Path("/home/user").rglob("*"):
        if not path.is_file():
            continue
        try:
            resolved = path.resolve()
            if resolved in excluded or path.stat().st_size > 1024 * 1024:
                continue
            data = path.read_text(errors="ignore")
        except OSError:
            continue
        if path.suffix == ".sh" or data.startswith("#!/bin/bash") or data.startswith("#!/usr/bin/env bash"):
            if "compile.sh" in data or "*.src" in data:
                candidates.append(path)
    return candidates


def _write_instrumented_compiler(log_path):
    COMPILE_SH.write_text(f'''#!/bin/bash
printf "%s\\n" "$#" >> {str(log_path)!r}
if [ "$#" -eq 0 ]; then exit 0; fi
grep -q "POISON_SYNTAX_ERROR" "$@" 2>/dev/null
if [ $? -eq 0 ]; then exit 1; fi
exit 0
''')
    COMPILE_SH.chmod(0o755)


def _populate_sources(poison_index):
    if SRC_DIR.exists():
        shutil.rmtree(SRC_DIR)
    SRC_DIR.mkdir(parents=True)
    for i in range(1, 501):
        text = "POISON_SYNTAX_ERROR\n" if i == poison_index else f"valid code block {i}\n"
        (SRC_DIR / f"file_{i}.src").write_text(text)


def test_phase2_poison_file_identified_and_removed():
    assert POISON_TXT.is_file(), f"Phase 2 failed: {POISON_TXT} is missing."
    poison_content = POISON_TXT.read_text().strip()
    assert poison_content == "file_314.src", (
        f"Phase 2 failed: {POISON_TXT} contains '{poison_content}', expected 'file_314.src'."
    )
    assert not (SRC_DIR / "file_314.src").exists(), (
        f"Phase 2 failed: Poisoned file {SRC_DIR / 'file_314.src'} was not deleted from the src/ directory."
    )

    candidates = _candidate_delta_scripts()
    assert candidates, "Phase 2 failed: no bash delta-debugging script was written."

    original_compile = COMPILE_SH.read_bytes()
    original_compile_mode = stat.S_IMODE(COMPILE_SH.stat().st_mode)
    original_sources = {p.name: p.read_bytes() for p in SRC_DIR.glob("*.src")}
    original_poison = POISON_TXT.read_bytes()
    poison_index = secrets.choice([i for i in range(1, 501) if i != 314])
    expected_name = f"file_{poison_index}.src"
    accepted = None
    errors = []

    try:
        for candidate in candidates:
            log_path = Path(tempfile.mkstemp(prefix="compile_calls_", dir="/tmp")[1])
            try:
                _populate_sources(poison_index)
                POISON_TXT.unlink(missing_ok=True)
                _write_instrumented_compiler(log_path)
                result = subprocess.run(
                    ["bash", str(candidate)],
                    cwd=str(PIPELINE_DIR),
                    capture_output=True,
                    text=True,
                    timeout=20,
                )
                counts = [int(x) for x in log_path.read_text().splitlines() if x.strip().isdigit()]
                correct_result = (
                    result.returncode == 0
                    and POISON_TXT.is_file()
                    and POISON_TXT.read_text().strip() == expected_name
                    and not (SRC_DIR / expected_name).exists()
                )
                efficient_bisection = (
                    7 <= len(counts) <= 25
                    and max(counts, default=0) >= 200
                    and min(counts, default=9999) <= 4
                    and len(set(counts)) >= 6
                )
                if correct_result and efficient_bisection:
                    accepted = candidate
                    break
                errors.append(
                    f"{candidate}: exit={result.returncode}, calls={counts}, "
                    f"poison.txt={POISON_TXT.read_text().strip() if POISON_TXT.is_file() else '<missing>'}"
                )
            except (subprocess.TimeoutExpired, OSError) as exc:
                errors.append(f"{candidate}: {exc}")
            finally:
                log_path.unlink(missing_ok=True)
    finally:
        COMPILE_SH.write_bytes(original_compile)
        COMPILE_SH.chmod(original_compile_mode)
        if SRC_DIR.exists():
            shutil.rmtree(SRC_DIR)
        SRC_DIR.mkdir(parents=True)
        for name, data in original_sources.items():
            (SRC_DIR / name).write_bytes(data)
        POISON_TXT.write_bytes(original_poison)

    assert accepted is not None, (
        "Phase 2 failed: no submitted bash script identified and removed a randomized poison file "
        "using an efficient sequence of compiler bisection calls. " + " | ".join(errors)
    )


def _run_awk(values):
    with tempfile.NamedTemporaryFile("w", delete=False, prefix="metrics_", suffix=".txt") as f:
        f.write("\n".join(values) + "\n")
        path = f.name
    try:
        result = subprocess.run(
            ["awk", "-f", str(AGGREGATE_AWK), path],
            capture_output=True,
            text=True,
            timeout=10,
        )
    finally:
        os.unlink(path)
    assert result.returncode == 0, f"aggregate.awk failed: {result.stderr}"
    output = result.stdout.strip()
    match = re.fullmatch(r"StdDev:\s+([-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?)", output)
    assert match, f"aggregate.awk changed the required output format: {output!r}"
    return float(match.group(1)), output


def test_phase3_aggregate_awk_fixed():
    assert AGGREGATE_AWK.is_file(), f"{AGGREGATE_AWK} is missing."
    assert METRICS_TXT.is_file(), f"{METRICS_TXT} is missing."

    result = subprocess.run(
        ["awk", "-f", str(AGGREGATE_AWK), str(METRICS_TXT)],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, (
        f"Phase 3 failed: aggregate.awk crashed or returned non-zero exit code. Stderr: {result.stderr}"
    )
    output = result.stdout.strip()
    assert "StdDev:" in output, "Phase 3 failed: aggregate.awk output does not contain 'StdDev:'."
    assert "0.007" in output, (
        f"Phase 3 failed: aggregate.awk output '{output}' does not contain the correct computed "
        "standard deviation (expected ~0.007)."
    )

    rng = secrets.SystemRandom()
    for scale in (0.01, 0.1, 1.0):
        base = rng.randrange(100_000_000, 900_000_000)
        offsets = [rng.randrange(-20, 21) * scale for _ in range(17)]
        if len(set(offsets)) < 2:
            offsets[-1] += scale
        values_float = [base + x for x in offsets]
        values_text = [f"{x:.6f}" for x in values_float]
        actual_values = [float(x) for x in values_text]
        mean = math.fsum(actual_values) / len(actual_values)
        expected = math.sqrt(math.fsum((x - mean) ** 2 for x in actual_values) / len(actual_values))
        observed, _ = _run_awk(values_text)
        tolerance = max(2e-5, expected * 2e-4)
        assert math.isfinite(observed) and abs(observed - expected) <= tolerance, (
            f"Phase 3 failed on generated large, closely-spaced values: expected {expected}, got {observed}."
        )


def test_build_success_flag():
    assert BUILD_FLAG.is_file(), f"Build failed: {BUILD_FLAG} is missing. Did you successfully run build.sh?"
    BUILD_FLAG.unlink()
    result = subprocess.run([str(BUILD_SH)], capture_output=True, text=True, timeout=20)
    assert result.returncode == 0, f"build.sh failed when executed: {result.stdout}\n{result.stderr}"
    assert BUILD_FLAG.is_file(), "build.sh did not regenerate build_success.flag."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
