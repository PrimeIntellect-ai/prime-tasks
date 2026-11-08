#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import re
import secrets
import subprocess
import sys
import traceback

DATA = "/home/user/company_data.csv"
REPORT = "/home/user/report.txt"
PROJECT = "/home/user/analysis"
MANIFEST = os.path.join(PROJECT, "Cargo.toml")
MAIN_RS = os.path.join(PROJECT, "src", "main.rs")

cargo_env = os.environ.copy()
cargo_env["CARGO_HOME"] = "/opt/cargo"
cargo_env["RUSTUP_HOME"] = "/opt/rustup"
cargo_env["PATH"] = "/opt/cargo/bin:" + cargo_env.get("PATH", "")


def assert_original_report():
    # Preserve the original verifier's assertions.
    assert os.path.exists(REPORT), "/home/user/report.txt does not exist."
    assert os.path.isfile(REPORT), "/home/user/report.txt is not a file."

    with open(REPORT, "r") as f:
        content = f.read().strip()

    lines = [line.strip() for line in content.splitlines() if line.strip()]
    assert len(lines) >= 3, "report.txt must contain at least 3 lines (Correlation, T-statistic, Top 3)."

    corr_match = re.search(r"Correlation:\s*([0-9\.\-]+)", content)
    assert corr_match is not None, "Could not find 'Correlation: [value]' in report.txt."
    corr_val = float(corr_match.group(1))
    assert abs(corr_val - 0.6953) <= 0.0002, f"Expected Correlation ~0.6953, got {corr_val}"

    tstat_match = re.search(r"T-statistic:\s*([0-9\.\-]+)", content)
    assert tstat_match is not None, "Could not find 'T-statistic: [value]' in report.txt."
    tstat_val = float(tstat_match.group(1))
    assert abs(tstat_val - 6.7212) <= 0.0002, f"Expected T-statistic ~6.7212, got {tstat_val}"

    top3_match = re.search(r"Top 3:\s*(.*)", content)
    assert top3_match is not None, "Could not find 'Top 3: [IDs]' in report.txt."
    top3_val = top3_match.group(1).strip()
    expected_top3 = "COMP_2, COMP_42, COMP_33"
    assert top3_val == expected_top3, f"Expected Top 3: {expected_top3}, got {top3_val}"


def validate_project():
    assert os.path.isdir(PROJECT) and not os.path.islink(PROJECT), "/home/user/analysis must be a Cargo project directory."
    assert os.path.isfile(MANIFEST) and not os.path.islink(MANIFEST), "Cargo.toml is missing or is not a regular file."
    assert os.path.isfile(MAIN_RS) and not os.path.islink(MAIN_RS), "src/main.rs is missing or is not a regular Rust source file."
    assert os.path.getsize(MAIN_RS) > 0, "src/main.rs is empty."

    result = subprocess.run(
        ["cargo", "metadata", "--offline", "--no-deps", "--format-version", "1", "--manifest-path", MANIFEST],
        cwd=PROJECT,
        env=cargo_env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, f"Invalid Cargo project:\n{result.stderr}"
    metadata = json.loads(result.stdout)
    assert any(
        "bin" in target.get("kind", [])
        for package in metadata.get("packages", [])
        for target in package.get("targets", [])
    ), "Cargo project does not define a Rust binary target."


def run_submission():
    if os.path.lexists(REPORT):
        os.remove(REPORT)
    result = subprocess.run(
        ["cargo", "run", "--quiet", "--offline", "--manifest-path", MANIFEST],
        cwd=PROJECT,
        env=cargo_env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert result.returncode == 0, f"Rust program failed when executed:\n{result.stderr}"
    assert os.path.isfile(REPORT), "Executing the Rust program did not create /home/user/report.txt."


def expected_values(rows):
    ratios = [row[1] / row[2] for row in rows]
    profits = [row[3] for row in rows]
    n = len(rows)
    mean_x = sum(ratios) / n
    mean_y = sum(profits) / n
    numerator = sum((x - mean_x) * (y - mean_y) for x, y in zip(ratios, profits))
    denom_x = sum((x - mean_x) ** 2 for x in ratios)
    denom_y = sum((y - mean_y) ** 2 for y in profits)
    r = numerator / math.sqrt(denom_x * denom_y)
    t = r * math.sqrt((n - 2) / (1 - r * r))
    top3 = [row[0] for row in sorted(rows, key=lambda row: row[1] / row[2], reverse=True)[:3]]
    return r, t, top3


def assert_dynamic_report(rows):
    r, t, top3 = expected_values(rows)
    with open(REPORT, "r") as f:
        content = f.read().strip()

    match = re.fullmatch(
        r"Correlation: (-?\d+\.\d{4})\nT-statistic: (-?\d+\.\d{4})\nTop 3: ([^\n]+)",
        content,
    )
    assert match is not None, "report.txt does not exactly match the required three-line format with four decimal places."
    assert match.group(1) == format(r, ".4f"), f"Correlation was not computed from the verification dataset: expected {r:.4f}, got {match.group(1)}"
    assert match.group(2) == format(t, ".4f"), f"T-statistic was not computed from the verification dataset: expected {t:.4f}, got {match.group(2)}"
    assert match.group(3) == ", ".join(top3), f"Top 3 was not computed from the verification dataset: expected {', '.join(top3)}, got {match.group(3)}"


def make_verification_rows():
    token = secrets.token_hex(6)
    rows = []
    # Runtime-generated values prevent a fixed report from satisfying this run.
    for i in range(17):
        total = 180.0 + i * 13.0 + secrets.randbelow(7000) / 100.0
        ratio = 0.08 + i * 0.037 + secrets.randbelow(1000) / 100000.0
        rd = total * ratio
        noise = (secrets.randbelow(20001) - 10000) / 173.0
        profit = 640.0 * ratio + noise + ((i % 4) - 1.5) * 11.0
        rows.append((f"VERIFY_{token}_{i}", rd, total, profit))
    return rows


def write_rows(rows):
    with open(DATA, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["Company_ID", "R&D_Spend", "Total_Expenses", "Profit"])
        writer.writerows(rows)


def main():
    with open(DATA, "rb") as f:
        original_data = f.read()

    failure = None
    project_valid = False
    try:
        assert_original_report()
        validate_project()
        project_valid = True

        verification_rows = make_verification_rows()
        write_rows(verification_rows)
        run_submission()
        assert_dynamic_report(verification_rows)
    except BaseException as exc:
        failure = exc
        traceback.print_exc()
    finally:
        with open(DATA, "wb") as f:
            f.write(original_data)

        if project_valid:
            try:
                run_submission()
                assert_original_report()
            except BaseException as exc:
                if failure is None:
                    failure = exc
                traceback.print_exc()

    if failure is not None:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
