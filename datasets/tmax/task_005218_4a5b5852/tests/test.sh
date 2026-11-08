#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import time
import uuid
import shutil
import subprocess

import pytest

APP_DIR = "/home/user/app"
DATA_DIR = os.path.join(APP_DIR, "data")
OUTPUT_DIR = os.path.join(APP_DIR, "output")
SUPERVISOR = os.path.join(APP_DIR, "supervisor.sh")
SENSOR = os.path.join(APP_DIR, "sensor.sh")
PROCESSOR = os.path.join(APP_DIR, "processor.sh")

EXPECTED_SENSOR = b'''#!/bin/bash
sleep 1 # Simulate boot time
TODAY=$(TZ=UTC date +%Y-%m-%d)
for i in {1..20}; do
  echo "DATA payload for $TODAY" > /home/user/app/data/log_$i.txt
done
touch /home/user/app/data/ready.flag
'''


def clear_dir(path):
    os.makedirs(path, exist_ok=True)
    for name in os.listdir(path):
        target = os.path.join(path, name)
        if os.path.isfile(target) or os.path.islink(target):
            os.unlink(target)
        elif os.path.isdir(target):
            shutil.rmtree(target)


def assert_script(path):
    assert os.path.isfile(path), f"Required script missing or not a regular file: {path}"
    assert os.access(path, os.X_OK), f"Required script is not executable: {path}"


def expected_log_names():
    return {f"log_{i}.txt" for i in range(1, 21)}


def test_pipeline_execution_and_metrics():
    for script in (SUPERVISOR, SENSOR, PROCESSOR):
        assert_script(script)

    with open(SENSOR, "rb") as f:
        assert f.read() == EXPECTED_SENSOR, "sensor.sh was modified, but the task forbids modifying it"

    # Clear data and output directories to ensure a clean run.
    clear_dir(DATA_DIR)
    clear_dir(OUTPUT_DIR)

    # Execute supervisor.sh and measure the duration.
    start_time = time.time()
    result = subprocess.run(
        [SUPERVISOR],
        capture_output=True,
        text=True,
        timeout=6,
    )
    duration = time.time() - start_time

    # Preserve the original execution assertion.
    assert result.returncode == 0, (
        f"supervisor.sh failed with return code {result.returncode}.\n"
        f"STDOUT: {result.stdout}\nSTDERR: {result.stderr}"
    )

    # Preserve the original exact regular-file count assertion.
    output_files = [
        f for f in os.listdir(OUTPUT_DIR)
        if os.path.isfile(os.path.join(OUTPUT_DIR, f))
    ]
    assert len(output_files) == 20, (
        f"Expected exactly 20 files in {OUTPUT_DIR}, but found {len(output_files)}.\n"
        f"Files found: {output_files}"
    )

    # Preserve the original runtime assertion.
    assert duration <= 3.5, (
        f"Pipeline execution took {duration:.3f} seconds, which exceeds the threshold of 3.5 seconds. "
        "The processor script might not be properly parallelized or the sleep mechanism is inefficient."
    )

    # Outputs must be the actual sensor logs, not fabricated placeholders.
    expected_names = expected_log_names()
    assert set(output_files) == expected_names, f"Unexpected output names: {output_files}"
    data_files = {
        f for f in os.listdir(DATA_DIR)
        if os.path.isfile(os.path.join(DATA_DIR, f)) and f.startswith("log_")
    }
    assert data_files == expected_names, f"Sensor did not generate the expected logs: {data_files}"
    assert os.path.isfile(os.path.join(DATA_DIR, "ready.flag")), "Sensor ready.flag is missing"
    for name in expected_names:
        with open(os.path.join(DATA_DIR, name), "rb") as src, open(os.path.join(OUTPUT_DIR, name), "rb") as dst:
            assert dst.read() == src.read(), f"Output {name} does not match its sensor input"


def test_supervisor_invokes_components_and_sets_processor_utc():
    token = uuid.uuid4().hex
    sensor_marker = f"/tmp/sensor_called_{token}"
    processor_marker = f"/tmp/processor_called_{token}"
    timezone_marker = f"/tmp/processor_timezone_{token}"
    sensor_backup = f"{SENSOR}.verifier_backup_{token}"
    processor_backup = f"{PROCESSOR}.verifier_backup_{token}"

    os.replace(SENSOR, sensor_backup)
    os.replace(PROCESSOR, processor_backup)
    try:
        with open(SENSOR, "w") as f:
            f.write(f"#!/bin/bash\nprintf called > '{sensor_marker}'\n")
        with open(PROCESSOR, "w") as f:
            f.write(
                "#!/bin/bash\n"
                f"printf called > '{processor_marker}'\n"
                f"date +%z > '{timezone_marker}'\n"
            )
        os.chmod(SENSOR, 0o755)
        os.chmod(PROCESSOR, 0o755)

        env = os.environ.copy()
        env["TZ"] = "America/New_York"
        result = subprocess.run(
            [SUPERVISOR], capture_output=True, text=True, env=env, timeout=5
        )
        assert result.returncode == 0, (
            f"supervisor.sh failed component probe: {result.stdout}\n{result.stderr}"
        )
        assert os.path.isfile(sensor_marker), "supervisor.sh did not launch sensor.sh"
        assert os.path.isfile(processor_marker), "supervisor.sh did not launch processor.sh"
        assert os.path.isfile(timezone_marker), "processor timezone probe was not written"
        with open(timezone_marker) as f:
            offset = f.read().strip()
        assert offset == "+0000", (
            "supervisor.sh did not start processor.sh in UTC; "
            f"processor observed offset {offset!r}"
        )
    finally:
        for path in (SENSOR, PROCESSOR):
            if os.path.lexists(path):
                os.unlink(path)
        os.replace(sensor_backup, SENSOR)
        os.replace(processor_backup, PROCESSOR)
        for path in (sensor_marker, processor_marker, timezone_marker):
            if os.path.exists(path):
                os.unlink(path)


def test_processor_waits_and_processes_real_inputs_concurrently():
    clear_dir(DATA_DIR)
    clear_dir(OUTPUT_DIR)

    env = os.environ.copy()
    env["TZ"] = "UTC"
    start = time.time()
    proc = subprocess.Popen(
        [PROCESSOR], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env
    )

    # It must remain alive while waiting for the sensor readiness flag.
    time.sleep(0.4)
    assert proc.poll() is None, "processor.sh exited instead of waiting for ready.flag"

    nonce = uuid.uuid4().hex
    today = time.strftime("%Y-%m-%d", time.gmtime())
    expected = {}
    for i in range(1, 21):
        name = f"log_{i}.txt"
        payload = f"DATA {nonce} item={i} date={today}\n".encode()
        expected[name] = payload
        with open(os.path.join(DATA_DIR, name), "wb") as f:
            f.write(payload)
    open(os.path.join(DATA_DIR, "ready.flag"), "wb").close()

    try:
        stdout, stderr = proc.communicate(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.communicate()
        pytest.fail("processor.sh did not finish within the required performance window")

    duration = time.time() - start
    assert proc.returncode == 0, (
        f"processor.sh failed after delayed readiness with code {proc.returncode}.\n"
        f"STDOUT: {stdout}\nSTDERR: {stderr}"
    )
    assert duration <= 3.5, (
        f"processor.sh took {duration:.3f} seconds; log processing is not sufficiently concurrent"
    )

    actual_names = {
        f for f in os.listdir(OUTPUT_DIR)
        if os.path.isfile(os.path.join(OUTPUT_DIR, f))
    }
    assert actual_names == set(expected), f"Processor produced wrong output set: {actual_names}"
    for name, payload in expected.items():
        with open(os.path.join(OUTPUT_DIR, name), "rb") as f:
            assert f.read() == payload, f"Processor fabricated or corrupted {name}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
