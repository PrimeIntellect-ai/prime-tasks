#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import signal
import stat
import subprocess
import threading
import time

SERVICE = "/home/user/calc_service.sh"
TEST_SCRIPT = "/home/user/test_calc.sh"


def test_test_calc_script_exists_and_executable():
    script_path = TEST_SCRIPT
    assert os.path.isfile(script_path), f"The file {script_path} does not exist."
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"The file {script_path} is not executable."


def test_calc_service_fixed_memory_leak():
    script_path = SERVICE
    assert os.path.isfile(script_path), f"The file {script_path} does not exist."

    with open(script_path, "r") as f:
        content = f.read()

    # Keep the original source assertions.
    assert "LOG_BUFFER+=" not in content, "The memory leak bug (LOG_BUFFER+=) is still present in the service script."
    assert re.search(r">>\s*/home/user/service\.log", content), "The service script does not appear to append (>>) to /home/user/service.log."


def _wait_for_fifos(proc, timeout=3):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if proc.poll() is not None:
            raise AssertionError(f"Service exited early with code {proc.returncode}")
        try:
            in_mode = os.stat("/tmp/calc_in").st_mode
            out_mode = os.stat("/tmp/calc_out").st_mode
            if stat.S_ISFIFO(in_mode) and stat.S_ISFIFO(out_mode):
                return
        except FileNotFoundError:
            pass
        time.sleep(0.02)
    raise AssertionError("Service did not create both named pipes")


def _read_result_and_send(input_stream, command, timeout=2):
    result = {}

    def reader():
        try:
            with open("/tmp/calc_out", "r") as output_stream:
                result["value"] = output_stream.readline().rstrip("\n")
        except BaseException as exc:
            result["error"] = exc

    thread = threading.Thread(target=reader, daemon=True)
    thread.start()
    input_stream.write(command + "\n")
    input_stream.flush()
    thread.join(timeout)
    assert not thread.is_alive(), f"Timed out waiting for a response to {command!r}"
    assert "error" not in result, f"Could not read service response: {result.get('error')}"
    return result.get("value", "")


def test_service_factorials_and_real_append_logging():
    assert os.path.isfile(SERVICE), f"The file {SERVICE} does not exist."
    os.chmod(SERVICE, os.stat(SERVICE).st_mode | stat.S_IXUSR)
    for path in ("/tmp/calc_in", "/tmp/calc_out"):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    sentinel = "verifier-existing-log-line"
    with open("/home/user/service.log", "w") as log_file:
        log_file.write(sentinel + "\n")

    proc = subprocess.Popen(
        [SERVICE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    try:
        _wait_for_fifos(proc)
        values = [0, 2, 5, 6, 10]
        with open("/tmp/calc_in", "w", buffering=1) as input_stream:
            for value in values:
                actual = _read_result_and_send(input_stream, f"fact {value}")
                expected = str(math.factorial(value))
                assert actual == expected, f"fact {value} returned {actual!r}, expected {expected!r}"
            input_stream.write("QUIT\n")
            input_stream.flush()

        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            raise AssertionError("Service did not terminate after QUIT")
        assert proc.returncode == 0, f"Service exited with code {proc.returncode}: {proc.stderr.read()}"

        with open("/home/user/service.log", "r") as log_file:
            log_lines = log_file.read().splitlines()
        assert log_lines and log_lines[0] == sentinel, "The service overwrote existing log contents instead of appending"
        for value in values:
            expected_line = f"fact {value} = {math.factorial(value)}"
            assert expected_line in log_lines, f"Missing appended log entry: {expected_line}"
    finally:
        if proc.poll() is None:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait(timeout=2)
        for path in ("/tmp/calc_in", "/tmp/calc_out"):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass


def test_test_calc_script_execution():
    script_path = TEST_SCRIPT
    try:
        result = subprocess.run(
            [script_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10
        )
    except subprocess.TimeoutExpired:
        assert False, f"Execution of {script_path} timed out."

    assert result.returncode == 0, f"{script_path} exited with code {result.returncode}, expected 0. Stderr: {result.stderr}"
    assert "PASS" in result.stdout, f"{script_path} did not print 'PASS'. Stdout: {result.stdout}"


def _write_mock_service(first_result, second_result, trace_path, marker_path):
    mock = f'''#!/bin/bash
rm -f /tmp/calc_in /tmp/calc_out
mkfifo /tmp/calc_in /tmp/calc_out
cleanup() {{ rm -f /tmp/calc_in /tmp/calc_out; }}
trap cleanup EXIT
exec 3<> /tmp/calc_in
while read -r cmd n <&3; do
    if [[ "$cmd" == "QUIT" ]]; then
        echo "QUIT" >> {trace_path!r}
        sleep 0.4
        touch {marker_path!r}
        break
    elif [[ "$cmd" == "fact" ]]; then
        echo "fact $n" >> {trace_path!r}
        if [[ "$n" == "5" ]]; then
            echo {first_result!r} > /tmp/calc_out
        elif [[ "$n" == "6" ]]; then
            echo {second_result!r} > /tmp/calc_out
        else
            echo unexpected > /tmp/calc_out
        fi
    fi
done
'''
    with open(SERVICE, "w") as service_file:
        service_file.write(mock)
    os.chmod(SERVICE, 0o755)


def _run_instrumented_regression(first_result, second_result, expected_code, expected_word, suffix):
    trace = f"/tmp/test_calc_trace_{suffix}"
    marker = f"/tmp/test_calc_waited_{suffix}"
    for path in (trace, marker, "/tmp/calc_in", "/tmp/calc_out"):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass
    _write_mock_service(first_result, second_result, trace, marker)

    started = time.monotonic()
    proc = subprocess.Popen(
        [TEST_SCRIPT], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, start_new_session=True
    )
    try:
        stdout, stderr = proc.communicate(timeout=8)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        proc.wait(timeout=2)
        raise AssertionError("Regression test timed out against the instrumented service")
    elapsed = time.monotonic() - started

    assert proc.returncode == expected_code, (
        f"Regression test returned {proc.returncode}, expected {expected_code}. "
        f"stdout={stdout!r}, stderr={stderr!r}"
    )
    assert expected_word in stdout, f"Regression test did not print {expected_word!r}: {stdout!r}"
    assert os.path.exists(trace), "Regression test never started or contacted calc_service.sh"
    with open(trace, "r") as trace_file:
        commands = trace_file.read().splitlines()
    assert commands == ["fact 5", "fact 6", "QUIT"], f"Wrong command sequence: {commands!r}"
    assert os.path.exists(marker), "Regression test did not wait for graceful service termination"
    assert elapsed >= 0.3, "Regression test returned before the service completed its delayed shutdown"


def test_regression_script_drives_service_and_checks_results():
    backup = "/tmp/calc_service.verifier_backup"
    try:
        os.unlink(backup)
    except FileNotFoundError:
        pass
    os.replace(SERVICE, backup)
    try:
        _run_instrumented_regression("120", "720", 0, "PASS", "good")
        _run_instrumented_regression("120", "721", 1, "FAIL", "bad")
    finally:
        try:
            os.unlink(SERVICE)
        except FileNotFoundError:
            pass
        os.replace(backup, SERVICE)
        for path in ("/tmp/calc_in", "/tmp/calc_out"):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
