#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import os
import secrets
import subprocess
import tempfile
from decimal import Decimal, localcontext
from fractions import Fraction

REPORT_PATH = "/home/user/fixed_report.txt"
SCRIPT_PATH = "/home/user/uptime_monitor.py"
LOG_PATH = "/home/user/container_logs.txt"


def load_monitor():
    spec = importlib.util.spec_from_file_location("uptime_monitor", SCRIPT_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def as_decimal(value):
    assert not isinstance(value, float), "SLA calculations still use inexact binary floating point."
    if isinstance(value, Decimal):
        return value
    if isinstance(value, Fraction):
        with localcontext() as ctx:
            ctx.prec = 50
            return Decimal(value.numerator) / Decimal(value.denominator)
    if isinstance(value, int):
        return Decimal(value)
    raise AssertionError(f"Expected an exact numeric result, got {type(value).__name__}.")


def expected_from_log(path):
    downtime = Decimal("0")
    with open(path, "r") as f:
        for line in f:
            parts = line.split()
            if not parts:
                continue
            assert len(parts) == 3, f"Unexpected log format in verifier input: {line!r}"
            if parts[1] == "FAIL":
                downtime += Decimal(parts[2])

    with localcontext() as ctx:
        ctx.prec = 50
        sla = Decimal("100.0") - (
            downtime / Decimal("86400000") * Decimal("100.0")
        )
    return f"SLA: {sla.quantize(Decimal('0.000001')):.6f}%"


def test_fixed_report_exists_and_correct():
    assert os.path.exists(REPORT_PATH), f"File {REPORT_PATH} is missing."
    assert os.path.isfile(REPORT_PATH), f"{REPORT_PATH} is not a file."

    with open(REPORT_PATH, "r") as f:
        content = f.read().strip()

    expected_content = expected_from_log(LOG_PATH)
    assert content == expected_content, (
        f"Expected report content to be '{expected_content}', but got '{content}'."
    )


def test_uptime_monitor_exists():
    assert os.path.exists(SCRIPT_PATH), f"File {SCRIPT_PATH} is missing."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."


def test_script_executes_successfully_on_supplied_log():
    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        capture_output=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"uptime_monitor.py failed when executed. stdout={result.stdout!r}, "
        f"stderr={result.stderr!r}"
    )


def test_parser_and_calculation_handle_whitespace_and_exact_arithmetic():
    monitor = load_monitor()
    assert callable(getattr(monitor, "parse_logs", None)), "parse_logs is missing."
    assert callable(getattr(monitor, "calculate_sla", None)), "calculate_sla is missing."

    a = Decimal(secrets.randbelow(800000) + 100001) / Decimal("1000")
    b = Decimal(secrets.randbelow(800000) + 100001) / Decimal("1000")
    c = Decimal(secrets.randbelow(800000) + 100001) / Decimal("1000")
    expected_downtime = a + b + c

    contents = (
        f"[2026-01-01T00:00:00Z]     FAIL   {a}\n"
        f"[2026-01-01T01:00:00Z]\tOK\t999.999\n"
        f"[2026-01-01T02:00:00Z]  \t FAIL\t  {b}\n"
        f"[2026-01-01T03:00:00Z] OK       12.345\n"
        f"[2026-01-01T04:00:00Z]\t\tFAIL    {c}\n"
    )

    with tempfile.NamedTemporaryFile("w", delete=False) as tmp:
        tmp.write(contents)
        temp_path = tmp.name

    try:
        parsed = monitor.parse_logs(temp_path)
    finally:
        os.unlink(temp_path)

    parsed_decimal = as_decimal(parsed)
    assert parsed_decimal == expected_downtime, (
        f"parse_logs returned {parsed!r}; expected exact downtime {expected_downtime}."
    )

    calculated = monitor.calculate_sla(parsed)
    calculated_decimal = as_decimal(calculated)
    with localcontext() as ctx:
        ctx.prec = 50
        expected_sla = Decimal("100.0") - (
            expected_downtime / Decimal("86400000") * Decimal("100.0")
        )
    assert calculated_decimal.quantize(Decimal("0.000000000001")) == expected_sla.quantize(
        Decimal("0.000000000001")
    ), f"calculate_sla returned {calculated!r}; expected {expected_sla}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
