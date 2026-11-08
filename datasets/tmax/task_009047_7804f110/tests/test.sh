#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import math
import os
import pathlib
import random
import shutil
import stat
import subprocess
import tempfile

SCRIPT = pathlib.Path('/home/user/pipeline/aggregate.sh')
OUTPUT = pathlib.Path('/home/user/pipeline/output.txt')
RESOLUTION = pathlib.Path('/home/user/resolution.txt')
CALC = pathlib.Path('/home/user/pipeline/calc_stats')
LOGS = pathlib.Path('/home/user/logs')


def read_single_float(path):
    assert path.is_file(), f"File {path} does not exist."
    content = path.read_text().strip()
    assert content, f"File {path} is empty."
    try:
        return float(content)
    except ValueError:
        assert False, f"Content of {path} is not a valid float: '{content}'"


def test_resolution_content():
    resolution_path = pathlib.Path('/home/user/resolution.txt')
    value = read_single_float(resolution_path)
    expected_value = 1000.0 / 0.045
    assert math.isclose(value, expected_value, rel_tol=1e-4), (
        f"Value in {resolution_path} ({value}) does not match the expected calculated metric."
    )


def test_output_txt_content():
    output_path = pathlib.Path('/home/user/pipeline/output.txt')
    value = read_single_float(output_path)
    expected_value = 1000.0 / 0.045
    assert math.isclose(value, expected_value, rel_tol=1e-4), (
        f"Value in {output_path} ({value}) does not match the expected calculated metric."
    )


def test_aggregate_script_is_executable_and_handles_utc_and_precision():
    assert SCRIPT.exists(), f"{SCRIPT} does not exist"
    assert stat.S_ISREG(SCRIPT.stat().st_mode), f"{SCRIPT} is not a regular file"
    assert os.access(SCRIPT, os.X_OK), f"{SCRIPT} is not executable"
    assert CALC.is_file(), f"{CALC} does not exist"

    temp = pathlib.Path(tempfile.mkdtemp(prefix='aggregate-verifier-'))
    logs_backup = temp / 'logs-backup'
    calc_backup = temp / 'calc_stats'
    marker = temp / 'calc-argument.txt'
    shim_dir = temp / 'bin'
    shim_dir.mkdir()

    saved_output = OUTPUT.read_bytes() if OUTPUT.exists() else None
    saved_resolution = RESOLUTION.read_bytes() if RESOLUTION.exists() else None
    calc_mode = CALC.stat().st_mode

    now_utc = datetime.datetime.now(datetime.timezone.utc)
    utc_date = now_utc.strftime('%Y%m%d')
    decoy_date = (now_utc - datetime.timedelta(days=1)).strftime('%Y%m%d')

    # Calls which explicitly request UTC see the real UTC date. Calls using a
    # local timezone receive a deterministic wrong date, independent of the
    # verifier's wall-clock hour.
    date_shim = shim_dir / 'date'
    date_shim.write_text(f'''#!/bin/bash
is_utc=0
for arg in "$@"; do
    case "$arg" in
        -u|--utc) is_utc=1 ;;
    esac
done
case "${{TZ:-}}" in
    UTC|UTC0|Etc/UTC|GMT|GMT0) is_utc=1 ;;
esac
if [ "$is_utc" -eq 1 ]; then
    exec /bin/date "$@"
fi
for arg in "$@"; do
    if [ "$arg" = "+%Y%m%d" ]; then
        printf '%s\\n' '{decoy_date}'
        exit 0
    fi
done
exec /bin/date "$@"
''')
    date_shim.chmod(0o755)

    # Instrument the required helper call. It records the exact duration
    # supplied by aggregate.sh and otherwise preserves calc_stats semantics.
    calc_wrapper = f'''#!/bin/bash
if [ "$#" -ne 1 ]; then
    exit 64
fi
printf '%s\\n' "$1" > {str(marker)!r}
exec /usr/bin/python3 - "$1" <<'PY'
import sys
try:
    duration = float(sys.argv[1])
except ValueError:
    raise SystemExit(65)
if duration == 0.0:
    raise SystemExit(66)
print(f"{{1000.0 / duration:.3f}}")
PY
'''

    try:
        shutil.copy2(CALC, calc_backup)
        shutil.move(str(LOGS), str(logs_backup))
        LOGS.mkdir(parents=True)
        CALC.write_text(calc_wrapper)
        CALC.chmod(0o755)

        env = os.environ.copy()
        env['PATH'] = str(shim_dir) + os.pathsep + env.get('PATH', '')

        rng = random.SystemRandom()
        durations_ms = rng.sample([n for n in range(11, 990) if n != 45], 2)
        for duration_ms in durations_ms:
            start = rng.randrange(1700000000000, 1800000000000)
            end = start + duration_ms
            decoy_ms = duration_ms + 1000

            (LOGS / f'app_UTC_{utc_date}.log').write_text(
                f'EVENT_START {start}\nEVENT_END {end}\n'
            )
            (LOGS / f'app_UTC_{decoy_date}.log').write_text(
                f'EVENT_START {start}\nEVENT_END {start + decoy_ms}\n'
            )
            marker.unlink(missing_ok=True)
            OUTPUT.unlink(missing_ok=True)

            result = subprocess.run(
                [str(SCRIPT)],
                cwd='/home/user/pipeline',
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=15,
            )
            assert result.returncode == 0, (
                f"aggregate.sh failed with exit code {result.returncode}. "
                f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
            )
            assert marker.is_file(), 'aggregate.sh did not invoke calc_stats'

            argument = marker.read_text().strip()
            assert argument, 'aggregate.sh passed an empty duration to calc_stats'
            fractional = argument.split('.', 1)
            assert len(fractional) == 2 and len(fractional[1]) >= 3, (
                f"calc_stats duration must be a floating-point string with at least "
                f"3 decimal places, got {argument!r}"
            )
            try:
                supplied_duration = float(argument)
            except ValueError:
                assert False, f"calc_stats received a non-numeric duration: {argument!r}"

            expected_duration = duration_ms / 1000.0
            assert math.isclose(supplied_duration, expected_duration, rel_tol=0, abs_tol=1e-12), (
                f"calc_stats received {supplied_duration}, expected {expected_duration}; "
                f"the script selected the wrong timezone/date or lost precision"
            )

            output_value = read_single_float(OUTPUT)
            expected_output = float(f'{1000.0 / expected_duration:.3f}')
            assert math.isclose(output_value, expected_output, rel_tol=0, abs_tol=0.0005), (
                f"Pipeline output {output_value} does not match helper result {expected_output}"
            )
    finally:
        if CALC.exists():
            CALC.unlink()
        if calc_backup.exists():
            shutil.copy2(calc_backup, CALC)
            CALC.chmod(calc_mode)
        if LOGS.exists():
            shutil.rmtree(LOGS)
        if logs_backup.exists():
            shutil.move(str(logs_backup), str(LOGS))
        if saved_output is None:
            OUTPUT.unlink(missing_ok=True)
        else:
            OUTPUT.write_bytes(saved_output)
        if saved_resolution is None:
            RESOLUTION.unlink(missing_ok=True)
        else:
            RESOLUTION.write_bytes(saved_resolution)
        shutil.rmtree(temp, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
