#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import glob
import subprocess
import pytest

PIPELINE_DIR = "/home/user/log_pipeline"
DATA_DIR = os.path.join(PIPELINE_DIR, "data")
OUTPUT_JSON = os.path.join(PIPELINE_DIR, "output.json")
REPORT_JSON = "/home/user/report.json"
RUN_SH = os.path.join(PIPELINE_DIR, "run.sh")
REQUIREMENTS = os.path.join(PIPELINE_DIR, "requirements.txt")
PROCESSOR = os.path.join(PIPELINE_DIR, "process_logs.py")
ANOMALOUS_IP = "10.0.42.17"

ORIGINAL_REQUIREMENTS = b"urllib3==1.26.15\nrequests==2.31.0\nchardet==3.0.4\n"
ORIGINAL_PROCESSOR = b'''import threading
import json
import glob
import collections
import os

error_counts = collections.defaultdict(int)

def process_file(filepath):
    try:
        with open(filepath, 'r') as f:
            for line in f:
                try:
                    data = json.loads(line)
                    if data.get("status", 200) >= 500:
                        # Race condition here
                        error_counts[data["ip"]] += 1
                except Exception:
                    pass
    except Exception as e:
        print(f"Error reading {filepath}: {e}")

def main():
    files = glob.glob('/home/user/log_pipeline/data/*.log')
    threads = []
    for f in files:
        t = threading.Thread(target=process_file, args=(f,))
        threads.append(t)
        t.start()

    for t in threads:
        t.join()

    with open('/home/user/log_pipeline/output.json', 'w') as f:
        json.dump(error_counts, f)

if __name__ == "__main__":
    main()
'''


def get_true_counts():
    counts = {}
    log_files = glob.glob(os.path.join(DATA_DIR, "*.log"))
    for filename in log_files:
        try:
            with open(filename, "r", encoding="utf-8") as f:
                lines = f.readlines()
        except UnicodeDecodeError:
            with open(filename, "r", encoding="utf-16") as f:
                lines = f.readlines()

        for line in lines:
            line = line.strip()
            if not line:
                continue
            try:
                data = json.loads(line)
                if data.get("status", 200) >= 500:
                    ip = data.get("ip")
                    if ip:
                        counts[ip] = counts.get(ip, 0) + 1
            except Exception:
                pass
    return counts


def test_pipeline_files_fixed_and_run_successfully():
    assert os.path.isfile(REQUIREMENTS), f"{REQUIREMENTS} is missing."
    assert os.path.isfile(PROCESSOR), f"{PROCESSOR} is missing."
    assert os.path.isfile(RUN_SH), f"{RUN_SH} is missing."
    assert os.access(RUN_SH, os.X_OK), f"{RUN_SH} is not executable."

    with open(REQUIREMENTS, "rb") as f:
        assert f.read() != ORIGINAL_REQUIREMENTS, "requirements.txt was not fixed."
    with open(PROCESSOR, "rb") as f:
        assert f.read() != ORIGINAL_PROCESSOR, "process_logs.py was not fixed."

    if os.path.exists(OUTPUT_JSON):
        os.remove(OUTPUT_JSON)

    result = subprocess.run(
        [RUN_SH],
        cwd=PIPELINE_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=300,
    )
    assert result.returncode == 0, f"run.sh failed with exit code {result.returncode}:\n{result.stdout}"
    assert os.path.isfile(OUTPUT_JSON), "run.sh did not generate output.json."


def test_report_json_exists_and_valid():
    assert os.path.isfile(REPORT_JSON), f"Report file {REPORT_JSON} is missing."
    with open(REPORT_JSON, 'r') as f:
        try:
            report_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{REPORT_JSON} is not valid JSON.")

    assert "anomalous_ip" in report_data, f"'anomalous_ip' missing in {REPORT_JSON}"
    assert "anomalous_error_count" in report_data, f"'anomalous_error_count' missing in {REPORT_JSON}"

    assert report_data["anomalous_ip"] == ANOMALOUS_IP, \
        f"Expected anomalous IP {ANOMALOUS_IP}, got {report_data['anomalous_ip']}."


def test_output_json_exists_and_valid():
    assert os.path.isfile(OUTPUT_JSON), f"Output file {OUTPUT_JSON} is missing."
    with open(OUTPUT_JSON, 'r') as f:
        try:
            output_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{OUTPUT_JSON} is not valid JSON.")

    assert isinstance(output_data, dict), f"{OUTPUT_JSON} should be a JSON object (dictionary)."


def test_error_counts_match_truth():
    true_counts = get_true_counts()

    with open(REPORT_JSON, 'r') as f:
        report_data = json.load(f)

    with open(OUTPUT_JSON, 'r') as f:
        output_data = json.load(f)

    expected_anomalous_count = true_counts.get(ANOMALOUS_IP, 0)
    assert report_data["anomalous_error_count"] == expected_anomalous_count, \
        f"Anomalous error count in report ({report_data['anomalous_error_count']}) does not match true count ({expected_anomalous_count})."

    for ip, count in true_counts.items():
        assert ip in output_data, f"IP {ip} is missing from {OUTPUT_JSON}."
        assert output_data[ip] == count, \
            f"Count for IP {ip} in {OUTPUT_JSON} is {output_data[ip]}, but true count is {count}."

    for ip in output_data.keys():
        assert ip in true_counts, f"IP {ip} found in {OUTPUT_JSON} but has no >= 500 errors in data."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
