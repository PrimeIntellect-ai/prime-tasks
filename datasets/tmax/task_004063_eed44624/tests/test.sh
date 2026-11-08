#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import shlex
import stat
import subprocess
import tempfile
from decimal import Decimal, ROUND_HALF_UP
import pytest

PIPELINE = "/home/user/run_pipeline.sh"
TEST_SCRIPT = "/home/user/test_accuracy.sh"
STATUS_FILE = "/home/user/test_status.txt"
ACTUAL_FILE = "/home/user/actual_out.csv"


def test_test_status_file():
    """Verify that the test status file exists and contains the success message."""
    status_file = "/home/user/test_status.txt"
    assert os.path.isfile(status_file), f"The file {status_file} does not exist. Did you run your test script?"
    with open(status_file, "r") as f:
        content = f.read().strip()
    assert content == "REPRODUCIBLE AND ACCURATE", f"Expected 'REPRODUCIBLE AND ACCURATE' in {status_file}, but got '{content}'"


def test_scripts_exist_and_executable():
    """Verify that both required scripts exist and are executable."""
    pipeline_script = "/home/user/run_pipeline.sh"
    test_script = "/home/user/test_accuracy.sh"

    for script in [pipeline_script, test_script]:
        assert os.path.isfile(script), f"The script {script} does not exist."
        st = os.stat(script)
        assert bool(st.st_mode & stat.S_IXUSR), f"The script {script} is not executable."


def test_pipeline_no_forbidden_tools():
    """Ensure the pipeline script does not use forbidden languages."""
    pipeline_script = "/home/user/run_pipeline.sh"
    with open(pipeline_script, "r") as f:
        content = f.read().lower()

    forbidden = ["python", "perl", "rscript"]
    for tool in forbidden:
        assert tool not in content, f"Forbidden tool '{tool}' found in {pipeline_script}. You must use standard shell tools."


def test_pipeline_logic_on_hidden_data():
    """Retain the original hidden-data behavior check."""
    pipeline_script = "/home/user/run_pipeline.sh"

    with tempfile.TemporaryDirectory() as tmpdir:
        tx_file = os.path.join(tmpdir, "tx_hidden.csv")
        fx_file = os.path.join(tmpdir, "fx_hidden.csv")
        out_file = os.path.join(tmpdir, "out_hidden.csv")

        with open(tx_file, "w") as f:
            f.write("tx_id,date,currency,amount\n")
            f.write("1,2023-11-01,CAD,100.00\n")
            f.write("2,2023-11-01,AUD,50.00\n")
            f.write("3,2023-11-02,CAD,200.50\n")

        with open(fx_file, "w") as f:
            f.write("date,currency,rate\n")
            f.write("2023-11-01,CAD,0.75\n")
            f.write("2023-11-01,AUD,0.65\n")
            f.write("2023-11-02,CAD,0.74\n")

        result = subprocess.run([pipeline_script, tx_file, fx_file, out_file], capture_output=True, text=True)
        assert result.returncode == 0, f"Pipeline script failed with return code {result.returncode}.\nStderr: {result.stderr}"
        assert os.path.isfile(out_file), f"Pipeline script did not create the expected output file at {out_file}."

        with open(out_file, "r") as f:
            out_lines = [line.strip() for line in f if line.strip()]

        assert len(out_lines) == 3, f"Output should have exactly 3 lines (header + 2 data rows), found {len(out_lines)}."
        assert out_lines[0] == "date,total_usd", f"Output header is incorrect. Expected 'date,total_usd', got '{out_lines[0]}'."
        assert out_lines[1] == "2023-11-01,107.50", f"Data mismatch for 2023-11-01. Expected '2023-11-01,107.50', got '{out_lines[1]}'."
        assert out_lines[2] == "2023-11-02,148.37", f"Data mismatch for 2023-11-02. Expected '2023-11-02,148.37', got '{out_lines[2]}'"


def test_pipeline_on_runtime_generated_inputs():
    """Exercise joins, date-specific rates, aggregation, sorting, and formatting on unpredictable inputs."""
    rng = random.SystemRandom()

    for case_number in range(5):
        while True:
            year = rng.randint(2024, 2035)
            month = rng.randint(1, 9)
            date_count = rng.randint(3, 5)
            dates = [f"{year:04d}-{month:02d}-{day:02d}" for day in rng.sample(range(1, 27), date_count)]
            dates.sort()
            currencies = [f"Q{rng.randrange(1000, 9999)}" for _ in range(rng.randint(3, 5))]
            currencies = list(dict.fromkeys(currencies))
            if len(currencies) < 3:
                continue

            rates = {}
            fx_rows = []
            for date in dates:
                for currency in currencies:
                    rate_hundredths = rng.randint(17, 243)
                    rate = Decimal(rate_hundredths) / Decimal(100)
                    rates[(date, currency)] = rate
                    fx_rows.append(f"{date},{currency},{rate:.2f}")

            tx_rows = []
            totals = {date: Decimal("0") for date in dates}
            tx_id = rng.randint(100, 900)
            for date in dates:
                for _ in range(rng.randint(2, 6)):
                    currency = rng.choice(currencies)
                    cents = rng.randint(1, 900000)
                    amount = Decimal(cents) / Decimal(100)
                    totals[date] += amount * rates[(date, currency)]
                    tx_rows.append(f"{tx_id},{date},{currency},{amount:.2f}")
                    tx_id += rng.randint(1, 4)

            # Avoid exact half-cent ties, whose rounding convention is not specified.
            if all((total * 100) % 1 != Decimal("0.5") for total in totals.values()):
                break

        rng.shuffle(tx_rows)
        rng.shuffle(fx_rows)
        expected_lines = ["date,total_usd"] + [
            f"{date},{totals[date].quantize(Decimal('0.01'), rounding=ROUND_HALF_UP):.2f}"
            for date in dates
        ]

        with tempfile.TemporaryDirectory() as tmpdir:
            tx_file = os.path.join(tmpdir, f"transactions_{case_number}_{rng.randrange(10**9)}.csv")
            fx_file = os.path.join(tmpdir, f"rates_{case_number}_{rng.randrange(10**9)}.csv")
            out_file = os.path.join(tmpdir, f"result_{case_number}_{rng.randrange(10**9)}.csv")
            with open(tx_file, "w", newline="") as f:
                f.write("tx_id,date,currency,amount\n" + "\n".join(tx_rows) + "\n")
            with open(fx_file, "w", newline="") as f:
                f.write("date,currency,rate\n" + "\n".join(fx_rows) + "\n")

            result = subprocess.run([PIPELINE, tx_file, fx_file, out_file], capture_output=True, text=True, timeout=15)
            assert result.returncode == 0, f"Generated case {case_number} failed. Stderr: {result.stderr}"
            assert os.path.isfile(out_file), f"Generated case {case_number} did not create its requested output."
            with open(out_file, "r", newline="") as f:
                actual_lines = f.read().rstrip("\n").splitlines()
            assert actual_lines == expected_lines, (
                f"Generated case {case_number} output mismatch.\n"
                f"Expected: {expected_lines}\nActual: {actual_lines}"
            )


def test_accuracy_script_is_executed_and_performs_comparison():
    """Run the required test script and verify both its pipeline invocation and pass/fail behavior."""
    expected_path = "/home/user/data/expected.csv"
    tx_path = "/home/user/data/tx.csv"
    fx_path = "/home/user/data/fx.csv"
    with open(expected_path, "rb") as f:
        original_expected = f.read()

    with tempfile.TemporaryDirectory() as tmpdir:
        backup_pipeline = os.path.join(tmpdir, "original_pipeline.sh")
        marker = os.path.join(tmpdir, "pipeline_calls.txt")
        os.replace(PIPELINE, backup_pipeline)
        wrapper = (
            "#!/bin/bash\n"
            + "printf '%s|%s|%s|%s\\n' \"$#\" \"$1\" \"$2\" \"$3\" >> " + shlex.quote(marker) + "\n"
            + "exec " + shlex.quote(backup_pipeline) + " \"$@\"\n"
        )
        with open(PIPELINE, "w") as f:
            f.write(wrapper)
        os.chmod(PIPELINE, 0o755)

        try:
            for path in (STATUS_FILE, ACTUAL_FILE):
                if os.path.exists(path):
                    os.remove(path)
            first = subprocess.run([TEST_SCRIPT], capture_output=True, text=True, timeout=20)
            assert first.returncode == 0, f"test_accuracy.sh failed on matching sample data: {first.stderr}"
            assert os.path.isfile(STATUS_FILE), "test_accuracy.sh did not create test_status.txt."
            with open(STATUS_FILE) as f:
                assert f.read().strip() == "REPRODUCIBLE AND ACCURATE"
            assert os.path.isfile(ACTUAL_FILE), "test_accuracy.sh did not create actual_out.csv."
            with open(ACTUAL_FILE, "rb") as f:
                actual = f.read().rstrip(b"\n")
            assert actual == original_expected.rstrip(b"\n"), "actual_out.csv does not match expected.csv."

            with open(expected_path, "wb") as f:
                f.write(original_expected.rstrip(b"\n") + b"\n2099-12-31,999.99\n")
            if os.path.exists(STATUS_FILE):
                os.remove(STATUS_FILE)
            second = subprocess.run([TEST_SCRIPT], capture_output=True, text=True, timeout=20)
            assert second.returncode == 0, f"test_accuracy.sh failed to report a mismatch cleanly: {second.stderr}"
            assert os.path.isfile(STATUS_FILE), "test_accuracy.sh did not write status for mismatching files."
            with open(STATUS_FILE) as f:
                assert f.read().strip() == "FAIL", "test_accuracy.sh must write FAIL when output and expected differ."

            with open(marker) as f:
                calls = [line.rstrip("\n") for line in f]
            required_call = f"3|{tx_path}|{fx_path}|{ACTUAL_FILE}"
            assert len(calls) >= 2, "test_accuracy.sh did not execute run_pipeline.sh on each test run."
            assert calls[0] == required_call and calls[-1] == required_call, (
                "test_accuracy.sh must invoke run_pipeline.sh with tx.csv, fx.csv, and actual_out.csv."
            )
        finally:
            with open(expected_path, "wb") as f:
                f.write(original_expected)
            if os.path.lexists(PIPELINE):
                os.remove(PIPELINE)
            os.replace(backup_pipeline, PIPELINE)

    final_run = subprocess.run([TEST_SCRIPT], capture_output=True, text=True, timeout=20)
    assert final_run.returncode == 0, f"Final test_accuracy.sh run failed: {final_run.stderr}"
    assert os.path.isfile(STATUS_FILE)
    with open(STATUS_FILE) as f:
        assert f.read().strip() == "REPRODUCIBLE AND ACCURATE"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
