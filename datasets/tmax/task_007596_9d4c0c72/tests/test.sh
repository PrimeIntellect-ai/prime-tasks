#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import math
import os
import re
import subprocess

BASE = "/home/user/ticket8022"
MODEL = os.path.join(BASE, "model.py")
REPORT = os.path.join(BASE, "report.txt")
USB = os.path.join(BASE, "usb.img")
PCAP = os.path.join(BASE, "traffic.pcap")


def recover_learning_rate():
    with open(USB, "rb") as f:
        image = f.read()
    matches = re.findall(rb'\{[^{}]*"learning_rate"\s*:\s*[-+0-9.eE]+[^{}]*\}', image)
    assert matches, "No recoverable configuration containing learning_rate was found in usb.img."
    for match in matches:
        try:
            config = json.loads(match.decode("utf-8"))
            return float(config["learning_rate"])
        except (UnicodeDecodeError, ValueError, KeyError, TypeError):
            pass
    raise AssertionError("The recoverable configuration in usb.img is invalid.")


def extract_sensor_data():
    from scapy.all import Raw, rdpcap

    for packet in rdpcap(PCAP):
        if Raw not in packet:
            continue
        payload = bytes(packet[Raw].load)
        body = payload.split(b"\r\n\r\n", 1)[-1].strip()
        try:
            document = json.loads(body.decode("utf-8"))
        except (UnicodeDecodeError, ValueError):
            continue
        if isinstance(document, dict) and isinstance(document.get("sensor_data"), list):
            return document["sensor_data"]
    raise AssertionError("No HTTP JSON sensor_data payload was found in traffic.pcap.")


def expected_optimize(data, lr):
    valid = [float(value) for value in data if value >= 0]
    assert valid, "Test data unexpectedly has no valid values."
    avg = sum(valid) / len(valid)
    x = avg
    for _ in range(100):
        if x == 0:
            break
        step = lr * (x ** 2 - avg) / (2 * x)
        x -= step
    return x


def load_model():
    spec = importlib.util.spec_from_file_location("ticket8022_model", MODEL)
    assert spec is not None and spec.loader is not None, "model.py is not a loadable Python module."
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_report_exists():
    assert os.path.isfile(REPORT), f"The report file {REPORT} is missing."


def test_recovered_inputs_are_original_task_inputs():
    learning_rate = recover_learning_rate()
    sensor_data = extract_sensor_data()
    assert abs(learning_rate - 0.05) < 1e-6, f"Expected recovered learning rate 0.05, got {learning_rate}"
    assert sensor_data == [12.5, 14.2, 13.8, -999.0, 15.1, 14.9], "traffic.pcap no longer contains the supplied sensor data."


def test_model_filters_negatives_and_runs_the_algorithm():
    assert os.path.isfile(MODEL), f"The required model file {MODEL} is missing."
    module = load_model()
    assert callable(getattr(module, "optimize", None)), "model.py does not define a callable optimize function."

    cases = [
        ([4.0, 9.0, -100.0, 16.0], 0.2),
        ([0.5, -7.0, 2.5, 7.0], 0.08),
    ]
    for data, lr in cases:
        actual = module.optimize(list(data), lr)
        expected = expected_optimize(data, lr)
        assert isinstance(actual, (int, float)) and math.isfinite(actual), "optimize did not return a finite number."
        assert math.isclose(actual, expected, rel_tol=1e-10, abs_tol=1e-10), (
            "optimize must remove negative values and perform the supplied 100-iteration update."
        )


def test_model_execution_and_report_contents():
    learning_rate = recover_learning_rate()
    sensor_data = extract_sensor_data()
    valid_data = [value for value in sensor_data if value >= 0]
    expected_value = expected_optimize(sensor_data, learning_rate)
    expected_rounded = float(f"{expected_value:.4f}")

    completed = subprocess.run(
        ["python3", MODEL],
        cwd=BASE,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert completed.returncode == 0, f"model.py failed when executed:\n{completed.stderr}"
    result_match = re.search(r"Result:\s*([-+]?(?:\d+(?:\.\d*)?|\.\d+))", completed.stdout)
    assert result_match is not None, f"model.py did not print a Result value. Output was: {completed.stdout!r}"
    executed_value = float(result_match.group(1))
    assert abs(executed_value - expected_rounded) < 1e-4, (
        f"Executed model.py printed {executed_value}, expected {expected_value:.4f}."
    )

    assert os.path.isfile(REPORT), f"The report file {REPORT} is missing."
    with open(REPORT, "r") as f:
        content = f.read()

    lr_match = re.search(r"LEARNING_RATE:\s*([0-9.]+)", content)
    dp_match = re.search(r"DATA_POINTS:\s*([0-9]+)", content)
    cv_match = re.search(r"CONVERGED_VALUE:\s*([0-9.]+)", content)

    assert lr_match is not None, "LEARNING_RATE not found in report.txt in the expected format."
    assert dp_match is not None, "DATA_POINTS not found in report.txt in the expected format."
    assert cv_match is not None, "CONVERGED_VALUE not found in report.txt in the expected format."

    learning_rate_in_report = float(lr_match.group(1))
    data_points = int(dp_match.group(1))
    converged_value = float(cv_match.group(1))

    assert abs(learning_rate_in_report - 0.05) < 1e-6, f"Expected LEARNING_RATE to be 0.05, got {learning_rate_in_report}"
    assert data_points == 5, f"Expected DATA_POINTS to be 5, got {data_points}"
    assert abs(converged_value - expected_rounded) < 1e-4, (
        f"Expected CONVERGED_VALUE to match the executed 100-iteration algorithm ({expected_value:.4f}), got {converged_value}"
    )
    assert abs(converged_value - executed_value) < 1e-4, "Report value does not match model.py output."

    lines = content.splitlines()
    assert len(lines) == 3, "report.txt must contain exactly the three requested lines."
    assert re.fullmatch(r"LEARNING_RATE:\s*[0-9.]+", lines[0])
    assert re.fullmatch(r"DATA_POINTS:\s*[0-9]+", lines[1])
    assert re.fullmatch(r"CONVERGED_VALUE:\s*[0-9.]+", lines[2])
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
