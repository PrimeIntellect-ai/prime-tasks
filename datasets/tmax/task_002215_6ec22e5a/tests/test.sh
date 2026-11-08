#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import shlex
import stat
import subprocess
import tempfile
from pathlib import Path


def run_aggregate(metrics_path):
    script_path = "/home/user/aggregate.sh"
    return subprocess.run(
        [script_path, metrics_path],
        capture_output=True,
        text=True,
        timeout=10,
    )


def test_aggregate_sh_correct_output():
    """Verify that aggregate.sh produces the correct output for the original metrics file."""
    script_path = "/home/user/aggregate.sh"
    metrics_path = "/home/user/data/metrics.txt"

    assert os.path.isfile(script_path), f"{script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."

    result = run_aggregate(metrics_path)
    assert result.returncode == 0, f"aggregate.sh failed with exit code {result.returncode}. Stderr: {result.stderr}"

    output = result.stdout.strip()
    assert output == "Total: 295", f"Expected 'Total: 295', but got '{output}'"


def test_aggregate_sh_handles_edge_cases():
    """Verify that aggregate.sh handles empty values, NaN, and spaces correctly using a custom file."""
    with tempfile.NamedTemporaryFile(mode="w", delete=False) as tmp:
        tmp.write("a= 10 \n")
        tmp.write("b=\n")
        tmp.write("c=NaN\n")
        tmp.write("d=  20\n")
        tmp.write("e=invalid\n")
        tmp_path = tmp.name

    try:
        result = run_aggregate(tmp_path)
        assert result.returncode == 0, f"aggregate.sh failed on edge cases. Stderr: {result.stderr}"

        output = result.stdout.strip()
        assert output == "Total: 30", f"Expected 'Total: 30' for edge cases, but got '{output}'"
    finally:
        os.remove(tmp_path)


def test_aggregate_sh_on_generated_inputs():
    """Exercise aggregation on unpredictable mixtures of integers and invalid values."""
    rng = random.SystemRandom()

    for case_number in range(8):
        expected = 0
        lines = []

        for item_number in range(rng.randint(7, 15)):
            key = f"metric_{case_number}_{item_number}_{rng.randrange(1_000_000)}"
            kind = rng.choice(["integer", "integer", "integer", "empty", "nan", "invalid"])
            left_space = " " * rng.randrange(0, 4)
            right_space = " " * rng.randrange(0, 4)

            if kind == "integer":
                value = rng.randrange(1, 50000)
                expected += value
                rendered = str(value)
            elif kind == "empty":
                rendered = ""
            elif kind == "nan":
                rendered = "NaN"
            else:
                rendered = rng.choice(["invalid", "offline", "12x", "--7", "N/A"])

            lines.append(f"{key}={left_space}{rendered}{right_space}\n")

        rng.shuffle(lines)
        with tempfile.NamedTemporaryFile(mode="w", delete=False) as tmp:
            tmp.writelines(lines)
            tmp_path = tmp.name

        try:
            result = run_aggregate(tmp_path)
            assert result.returncode == 0, (
                f"aggregate.sh failed on generated case {case_number}: {result.stderr}"
            )
            assert result.stdout.strip() == f"Total: {expected}", (
                f"Generated case {case_number} expected Total: {expected}, "
                f"got {result.stdout!r}"
            )
        finally:
            os.remove(tmp_path)


def test_regression_test_script():
    """Verify that test_aggregate.sh exists, is executable, and passes."""
    test_script_path = "/home/user/test_aggregate.sh"

    assert os.path.isfile(test_script_path), f"{test_script_path} does not exist."
    assert os.access(test_script_path, os.X_OK), f"{test_script_path} is not executable."

    source = Path(test_script_path).read_text(errors="replace")
    first_line = source.splitlines()[0] if source.splitlines() else ""
    assert first_line.startswith("#!") and "bash" in first_line, (
        "test_aggregate.sh must be a Bash script."
    )

    result = subprocess.run([test_script_path], capture_output=True, text=True, timeout=15)
    assert result.returncode == 0, (
        f"{test_script_path} failed with exit code {result.returncode}. "
        f"Stderr: {result.stderr}\nStdout: {result.stdout}"
    )


def test_regression_script_really_constructs_and_checks_a_fixture():
    """Ensure the regression script invokes aggregate.sh and rejects bad output."""
    aggregate_path = Path("/home/user/aggregate.sh")
    test_script_path = "/home/user/test_aggregate.sh"
    original = aggregate_path.read_bytes()
    original_stat = aggregate_path.stat()

    with tempfile.TemporaryDirectory() as workdir:
        log_dir = Path(workdir) / "calls"
        log_dir.mkdir()
        marker = Path(workdir) / "started"
        marker.touch()

        probe = f'''#!/bin/bash
log_dir={shlex.quote(str(log_dir))}
marker={shlex.quote(str(marker))}
call=$(mktemp -d "$log_dir/call.XXXXXX") || exit 90
printf '%s\\n' "$1" > "$call/arg"
if [[ -f "$1" ]]; then
    cp -- "$1" "$call/input"
else
    : > "$call/input"
fi
if [[ -f "$1" && "$1" -nt "$marker" ]]; then
    echo 1 > "$call/recent"
else
    echo 0 > "$call/recent"
fi

total=0
if [[ -f "$1" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" == *=* ]] || continue
        value=${{line#*=}}
        if [[ "$value" =~ ^[[:space:]]*([+-]?)([0-9]+)[[:space:]]*$ ]]; then
            sign=${{BASH_REMATCH[1]}}
            digits=${{BASH_REMATCH[2]}}
            number=$((10#$digits))
            [[ "$sign" == "-" ]] && number=$((-number))
            total=$((total + number))
        fi
    done < "$1"
fi
printf 'Total: %s\\n' "$total"
'''

        try:
            aggregate_path.write_text(probe)
            aggregate_path.chmod(0o755)

            good = subprocess.run(
                [test_script_path], capture_output=True, text=True, timeout=15
            )
            assert good.returncode == 0, (
                "The regression test did not pass when aggregate.sh returned the "
                f"correct computed sum. Stderr: {good.stderr}\nStdout: {good.stdout}"
            )

            calls = list(log_dir.glob("call.*"))
            assert calls, "The regression test never invoked /home/user/aggregate.sh."

            suitable_fixture = False
            for call in calls:
                arg = (call / "arg").read_text(errors="replace").strip()
                recent = (call / "recent").read_text(errors="replace").strip()
                content = (call / "input").read_text(errors="replace")

                has_integer = False
                has_empty = False
                has_nan = False
                for line in content.splitlines():
                    if "=" not in line:
                        continue
                    value = line.split("=", 1)[1].strip()
                    has_integer |= re.fullmatch(r"[+-]?\d+", value) is not None
                    has_empty |= value == ""
                    has_nan |= value == "NaN"

                if (
                    arg != "/home/user/data/metrics.txt"
                    and recent == "1"
                    and has_integer
                    and has_empty
                    and has_nan
                ):
                    suitable_fixture = True
                    break

            assert suitable_fixture, (
                "The regression test must create a fresh dummy metrics file containing "
                "an integer value, an empty value, and a NaN value, then pass it to aggregate.sh."
            )

            bad_probe = '''#!/bin/bash
printf '%s\n' 'this is deliberately not a Total result'
exit 0
'''
            aggregate_path.write_text(bad_probe)
            aggregate_path.chmod(0o755)

            bad = subprocess.run(
                [test_script_path], capture_output=True, text=True, timeout=15
            )
            assert bad.returncode == 1, (
                "The regression test must exit 1 when aggregate.sh returns incorrect output; "
                f"it exited {bad.returncode}. Stderr: {bad.stderr}\nStdout: {bad.stdout}"
            )
        finally:
            aggregate_path.write_bytes(original)
            os.chmod(aggregate_path, stat.S_IMODE(original_stat.st_mode))
            os.chown(aggregate_path, original_stat.st_uid, original_stat.st_gid)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
