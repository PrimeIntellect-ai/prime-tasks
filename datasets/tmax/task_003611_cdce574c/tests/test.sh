#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import signal
import stat
import subprocess
import tempfile
import urllib.request
import uuid

import numpy as np
from scipy.io import wavfile

INPUT_PATH = "/app/input.wav"
OUTPUT_PATH = "/home/user/output.wav"
SOURCE_PATH = "/home/user/processor.c"
DEPLOY_PATH = "/home/user/deploy.sh"


def _save_file(path):
    if not os.path.exists(path):
        return None
    with open(path, "rb") as f:
        data = f.read()
    return data, stat.S_IMODE(os.stat(path).st_mode)


def _restore_file(path, saved):
    if saved is None:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
        return
    data, mode = saved
    with open(path, "wb") as f:
        f.write(data)
    os.chmod(path, mode)


def _remove(path):
    try:
        os.remove(path)
    except FileNotFoundError:
        pass


def _write_random_input():
    data = np.frombuffer(os.urandom(44100 * 2), dtype="<i2").copy()
    data[:8] = np.array([-32768, -32767, -3, -1, 0, 1, 3, 32767], dtype=np.int16)
    wavfile.write(INPUT_PATH, 44100, data)
    return data


def _assert_scaled_output(expected_input):
    assert os.path.isfile(OUTPUT_PATH), f"File {OUTPUT_PATH} was not generated."
    try:
        sample_rate, data_out = wavfile.read(OUTPUT_PATH)
    except Exception as e:
        assert False, f"Failed to read generated output WAV file: {e}"
    assert sample_rate == 44100, f"Generated output sample rate is {sample_rate}, not 44100."
    assert data_out.dtype == np.int16, f"Generated output is not 16-bit PCM: {data_out.dtype}"
    assert data_out.ndim == 1, "Generated output is not mono."
    assert len(data_out) == len(expected_input), "Generated output has the wrong number of samples."
    expected = (expected_input * 0.5).astype(np.int16)
    mse = np.mean((expected.astype(float) - data_out.astype(float)) ** 2)
    assert mse <= 1.0, f"Generated output MSE {mse} is greater than threshold 1.0"


def _run_process(command, timeout=20):
    proc = subprocess.Popen(
        command,
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        start_new_session=True,
    )
    try:
        return proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            return proc.communicate(timeout=3)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            return proc.communicate()


def test_processor_c_exists():
    path = SOURCE_PATH
    assert os.path.exists(path), f"File {path} does not exist."
    assert os.path.isfile(path), f"Path {path} is not a regular file."


def test_deploy_sh_exists_and_executable():
    path = DEPLOY_PATH
    assert os.path.exists(path), f"File {path} does not exist."
    assert os.path.isfile(path), f"Path {path} is not a regular file."
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {path} is not executable."


def test_processor_c_compiles_and_processes_audio():
    saved_input = _save_file(INPUT_PATH)
    saved_output = _save_file(OUTPUT_PATH)
    executable = os.path.join(tempfile.gettempdir(), "processor_verify_" + uuid.uuid4().hex)
    try:
        expected_input = _write_random_input()
        compile_result = subprocess.run(
            ["gcc", "-std=c11", "-O2", SOURCE_PATH, "-o", executable, "-lm"],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert compile_result.returncode == 0, (
            "processor.c did not compile successfully:\n" +
            compile_result.stderr.decode(errors="replace")
        )

        invocations = [
            [executable],
            [executable, INPUT_PATH, OUTPUT_PATH],
            [executable, INPUT_PATH],
            [executable, OUTPUT_PATH],
        ]
        valid = False
        errors = []
        for command in invocations:
            _remove(OUTPUT_PATH)
            out, err = _run_process(command)
            try:
                _assert_scaled_output(expected_input)
                valid = True
                break
            except AssertionError as e:
                errors.append(f"{' '.join(command)}: {e}; stderr={err.decode(errors='replace')[:500]}")
        assert valid, "The compiled C program did not produce the required WAV output. " + " | ".join(errors)
    finally:
        _remove(executable)
        _restore_file(INPUT_PATH, saved_input)
        _restore_file(OUTPUT_PATH, saved_output)


def test_deploy_script_compiles_and_runs_processor():
    saved_source = _save_file(SOURCE_PATH)
    saved_input = _save_file(INPUT_PATH)
    saved_output = _save_file(OUTPUT_PATH)
    marker = "/tmp/deploy_marker_" + uuid.uuid4().hex
    token = uuid.uuid4().hex
    function_name = "verifier_constructor_" + uuid.uuid4().hex
    try:
        with open(SOURCE_PATH, "ab") as f:
            injected = (
                "\n#include <stdio.h>\n"
                f"__attribute__((constructor)) static void {function_name}(void) {{ "
                f"FILE *f = fopen(\"{marker}\", \"w\"); "
                f"if (f) {{ fputs(\"{token}\", f); fclose(f); }} }}\n"
            )
            f.write(injected.encode())

        expected_input = _write_random_input()
        _remove(OUTPUT_PATH)
        _remove(marker)
        _run_process([DEPLOY_PATH], timeout=30)

        assert os.path.isfile(marker), (
            "deploy.sh did not compile and run the current processor.c source."
        )
        with open(marker, "r") as f:
            assert f.read() == token, "The processor execution marker was invalid."
        _assert_scaled_output(expected_input)
    finally:
        _remove(marker)
        _restore_file(SOURCE_PATH, saved_source)
        _restore_file(INPUT_PATH, saved_input)
        _restore_file(OUTPUT_PATH, saved_output)


def test_server_running():
    pid_file = "/home/user/server.pid"
    assert os.path.exists(pid_file), f"PID file {pid_file} does not exist."

    with open(pid_file, 'r') as f:
        pid_str = f.read().strip()

    assert pid_str.isdigit(), f"PID file {pid_file} does not contain a valid integer PID."
    pid = int(pid_str)

    try:
        os.kill(pid, 0)
    except OSError:
        assert False, f"Process with PID {pid} is not running."

    try:
        response = urllib.request.urlopen("http://localhost:8080/")
        assert response.status == 200, f"Web server returned status {response.status} instead of 200."
    except Exception as e:
        assert False, f"Failed to connect to web server on port 8080: {e}"


def test_output_wav_mse():
    input_path = INPUT_PATH
    output_path = OUTPUT_PATH

    assert os.path.exists(output_path), f"File {output_path} does not exist."

    try:
        sr1, data_in = wavfile.read(input_path)
    except Exception as e:
        assert False, f"Failed to read input WAV file: {e}"

    try:
        sr2, data_out = wavfile.read(output_path)
    except Exception as e:
        assert False, f"Failed to read output WAV file: {e}"

    assert sr1 == sr2, f"Sample rates do not match: {sr1} != {sr2}"
    assert len(data_in) == len(data_out), f"Data lengths do not match: {len(data_in)} != {len(data_out)}"

    expected = (data_in * 0.5).astype(np.int16)
    mse = np.mean((expected.astype(float) - data_out.astype(float))**2)

    threshold = 1.0
    assert mse <= threshold, f"MSE {mse} is greater than threshold {threshold}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
