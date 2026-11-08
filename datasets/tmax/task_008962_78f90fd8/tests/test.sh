#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import stat
import subprocess
from datetime import datetime, timedelta
from decimal import Decimal, ROUND_HALF_EVEN
from pathlib import Path

import pytest


def expected_population_variance(values):
    mean = sum(values, Decimal("0")) / Decimal(len(values))
    variance = sum((value - mean) ** 2 for value in values) / Decimal(len(values))
    return format(variance.quantize(Decimal("0.0001"), rounding=ROUND_HALF_EVEN), "f")


def run_variance(values):
    path = "/home/user/calc_variance.sh"
    input_data = "".join(f"{value}\n" for value in values)
    return subprocess.run([path], input=input_data, capture_output=True, text=True, timeout=10)


def test_solution_txt_correct():
    path = "/home/user/solution.txt"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "0.0067", f"Expected '0.0067' in {path}, but got '{content}'."

    core = Path("/home/user/app.core").read_text(errors="ignore")
    match = re.search(r"CRITICAL_TZ_OFFSET=([+-])(\d{2})(\d{2})", core)
    assert match, "Could not derive the timezone offset from app.core."
    sign = 1 if match.group(1) == "+" else -1
    offset = sign * timedelta(hours=int(match.group(2)), minutes=int(match.group(3)))

    filtered = []
    for line in Path("/home/user/requests.log").read_text().splitlines():
        timestamp, latency = line.split()
        utc_time = datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
        if (utc_time + offset).date().isoformat() == "2023-10-25":
            filtered.append(Decimal(latency))
    derived = expected_population_variance(filtered)
    assert content == derived, f"solution.txt does not match the variance derived from the core timezone and filtered logs: {derived}."


def test_regression_sh_exists_and_passes():
    path = Path("/home/user/regression.sh")
    assert path.is_file(), f"File {path} does not exist."
    assert os.access(path, os.X_OK), f"File {path} is not executable."

    result = subprocess.run([str(path)], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, f"{path} did not exit with code 0. Exit code: {result.returncode}, Output: {result.stdout} {result.stderr}"

    calc = Path("/home/user/calc_variance.sh")
    original = calc.read_bytes()
    original_mode = stat.S_IMODE(calc.stat().st_mode)
    required_input = "100000000.1\n100000000.2\n100000000.3\n"

    try:
        for emitted, wanted_code in (("0.0067", 0), ("9.8765", 1)):
            capture = Path(f"/tmp/regression-input-{secrets.token_hex(12)}")
            calc.write_text(
                "#!/bin/bash\n"
                "cat > \"$CAPTURE\"\n"
                f"printf '%s\\n' '{emitted}'\n"
            )
            calc.chmod(0o755)
            env = os.environ.copy()
            env["CAPTURE"] = str(capture)
            probe = subprocess.run([str(path)], capture_output=True, text=True, env=env, timeout=10)
            assert probe.returncode == wanted_code, (
                f"regression.sh must exit {wanted_code} when calc_variance.sh emits {emitted}; "
                f"got {probe.returncode}."
            )
            assert capture.is_file(), "regression.sh did not invoke /home/user/calc_variance.sh."
            assert capture.read_text() == required_input, "regression.sh did not feed the three required values exactly."
            capture.unlink()
    finally:
        calc.write_bytes(original)
        calc.chmod(original_mode)


def test_calc_variance_sh_stable():
    path = "/home/user/calc_variance.sh"
    assert os.path.isfile(path), f"File {path} does not exist."
    assert os.access(path, os.X_OK), f"File {path} is not executable."

    input_data = "100000000.1\n100000000.2\n100000000.3\n"
    result = subprocess.run([path], input=input_data, capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, f"{path} failed to run."
    output = result.stdout.strip()
    assert output == "0.0067", f"Expected '0.0067' from {path}, but got '{output}'."

    fixed_cases = [
        [Decimal("1"), Decimal("2"), Decimal("3")],
        [Decimal("100000000.00"), Decimal("100000000.04"), Decimal("99999999.96"), Decimal("100000000.08")],
        [Decimal("7312345678.63"), Decimal("7312345678.89"), Decimal("7312345679.04"), Decimal("7312345679.19"), Decimal("7312345679.25")],
        [Decimal("456789012.34")],
    ]

    random_base = secrets.randbelow(8_000_000_000) + 100_000_000
    random_scale = secrets.randbelow(4) + 1
    offsets = [-37, -11, 4, 19, 25]
    random_case = [Decimal(random_base) + Decimal(offset * random_scale) / Decimal(100) for offset in offsets]
    fixed_cases.append(random_case)

    for values in fixed_cases:
        expected = expected_population_variance(values)
        result = run_variance(values)
        assert result.returncode == 0, f"{path} failed on input {values}: {result.stderr}"
        assert re.fullmatch(r"-?\d+\.\d{4}\n?", result.stdout), (
            f"Output must be one numeric value with exactly four decimal places, got {result.stdout!r}."
        )
        assert result.stdout.strip() == expected, (
            f"Incorrect population variance for {values}: expected {expected}, got {result.stdout.strip()!r}."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
