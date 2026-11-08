#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import gzip
import os
import random
import re
import shutil
import subprocess
import tempfile


def run_binary(binary_path, csv_text):
    return subprocess.run(
        [binary_path],
        input=csv_text.encode("utf-8"),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )


def test_rust_binary_behavior():
    binary_path = "/home/user/finops-analyzer/target/release/finops-analyzer"
    assert os.path.isfile(binary_path), f"Rust binary not found at {binary_path}. Did you build in release mode?"
    assert os.access(binary_path, os.X_OK), f"Rust binary at {binary_path} is not executable."

    test_csv = (
        "ResourceID,Type,Status,Cost\n"
        "i-123,ec2,running,10.50\n"
        "i-124,ec2,idle,5.25\n"
        "i-125,ec2,IDLE,15.00\n"
        "db-1,rds,stopped,0.00\n"
        "db-2,rds,idle,100.50\n"
    )
    result = run_binary(binary_path, test_csv)
    assert result.returncode == 0, result.stderr.decode("utf-8", errors="replace")
    output = result.stdout.decode("utf-8").strip()
    assert output == "120.75", f"Expected output '120.75', but got '{output}'"

    # Exercise fresh, verifier-generated inputs so a fixed-output executable cannot pass.
    rng = random.SystemRandom()
    for case_number in range(4):
        idle_cents = [rng.randint(101, 25000) for _ in range(3)]
        non_idle_cents = [rng.randint(101, 25000) for _ in range(2)]
        statuses = ["idle", "IDLE", "IdLe"]
        rows = ["ResourceID,Type,Status,Cost"]
        for i, (status, cents) in enumerate(zip(statuses, idle_cents)):
            rows.append(f"idle-{case_number}-{i},vm,{status},{cents / 100:.2f}")
        rows.append(f"run-{case_number},vm,running,{non_idle_cents[0] / 100:.2f}")
        rows.append(f"near-{case_number},vm,idleness,{non_idle_cents[1] / 100:.2f}")
        rng.shuffle(rows[1:])
        csv_text = "\n".join(rows) + "\n"
        expected = f"{sum(idle_cents) / 100:.2f}"

        result = run_binary(binary_path, csv_text)
        assert result.returncode == 0, result.stderr.decode("utf-8", errors="replace")
        output = result.stdout.decode("utf-8").strip()
        assert output == expected, f"Expected generated total '{expected}', but got '{output}'"


def read_last_log_line(log_path):
    assert os.path.isfile(log_path), f"Log file not found at {log_path}"
    with open(log_path, "r", encoding="utf-8") as f:
        lines = f.read().strip().splitlines()
    assert lines, "Log file is empty."
    return lines[-1].strip()


def assert_log_line(line, expected):
    pattern = (
        r"^\[\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}"
        r"(?:[+-]\d{2}:\d{2}|Z)\] Total idle cost: \$"
        + re.escape(expected)
        + r"$"
    )
    assert re.match(pattern, line), f"Log line format incorrect. Got: '{line}'"


def test_script_execution():
    script_path = "/home/user/run_analysis.sh"
    binary_path = "/home/user/finops-analyzer/target/release/finops-analyzer"
    data_path = "/home/user/billing_data"
    log_path = "/home/user/logs/idle_costs.log"

    assert os.path.isfile(script_path), f"Script not found at {script_path}"
    assert os.access(script_path, os.X_OK), f"Script at {script_path} is not executable."

    with open(script_path, "r", encoding="utf-8") as f:
        script_content = f.read()
    assert re.search(r"\bfind\b", script_content), "run_analysis.sh must use find"
    assert re.search(r"\b(?:cat|awk)\b", script_content), "run_analysis.sh must use cat or awk"
    assert "/home/user/finops-analyzer/target/release/finops-analyzer" in script_content, "Compiled analyzer path missing from script"
    assert "|" in script_content, "run_analysis.sh must pipe CSV data into the analyzer"

    # Preserve the original fixed-data assertion.
    subprocess.run([script_path], check=True, timeout=20)
    assert_log_line(read_last_log_line(log_path), "120.75")

    temp_root = tempfile.mkdtemp(prefix="finops-verifier-")
    saved_data = os.path.join(temp_root, "billing_data")
    saved_binary = os.path.join(temp_root, "finops-analyzer")
    probe_input = os.path.join(temp_root, "probe-input")

    try:
        os.rename(data_path, saved_data)
        os.makedirs(os.path.join(data_path, "deep", "nested"))

        rng = random.SystemRandom()
        values = [rng.randint(200, 30000) for _ in range(4)]
        expected = f"{sum(values) / 100:.2f}"

        with open(os.path.join(data_path, "root.csv"), "w", encoding="utf-8") as f:
            f.write("ResourceID,Type,Status,Cost\n")
            f.write(f"dynamic-a,vm,idle,{values[0] / 100:.2f}\n")
            f.write("ignored-a,vm,running,99999.99\n")
        with open(os.path.join(data_path, "deep", "second.csv"), "w", encoding="utf-8") as f:
            f.write("ResourceID,Type,Status,Cost\n")
            f.write(f"dynamic-b,db,IDLE,{values[1] / 100:.2f}\n")
            f.write(f"dynamic-c,db,IdLe,{values[2] / 100:.2f}\n")
        with open(os.path.join(data_path, "deep", "nested", "third.csv"), "w", encoding="utf-8") as f:
            f.write("ResourceID,Type,Status,Cost\n")
            f.write(f"dynamic-d,disk,idle,{values[3] / 100:.2f}\n")
        with open(os.path.join(data_path, "not-a-csv.txt"), "w", encoding="utf-8") as f:
            f.write("trap,vm,idle,88888.88\n")

        subprocess.run([script_path], check=True, timeout=20)
        assert_log_line(read_last_log_line(log_path), expected)

        # Replace the analyzer briefly with a probe. This verifies that the script
        # really sends the recursively discovered CSV contents to the demanded binary
        # and uses that binary's output in the log.
        shutil.copy2(binary_path, saved_binary)
        with open(binary_path, "w", encoding="utf-8") as f:
            f.write("#!/bin/sh\n")
            f.write(f"cat > {probe_input!r}\n")
            f.write("printf '9876.54\\n'\n")
        os.chmod(binary_path, 0o755)

        subprocess.run([script_path], check=True, timeout=20)
        assert_log_line(read_last_log_line(log_path), "9876.54")
        with open(probe_input, "r", encoding="utf-8") as f:
            piped = f.read()
        for marker in ("dynamic-a", "dynamic-b", "dynamic-c", "dynamic-d"):
            assert marker in piped, f"CSV row {marker} was not piped to the analyzer"
        assert "88888.88" not in piped, "A non-.csv file was incorrectly included"
    finally:
        if os.path.exists(saved_binary):
            shutil.copy2(saved_binary, binary_path)
        if os.path.exists(data_path):
            shutil.rmtree(data_path)
        if os.path.exists(saved_data):
            os.rename(saved_data, data_path)
        shutil.rmtree(temp_root, ignore_errors=True)


def test_logrotate_config():
    conf_path = "/home/user/logrotate.conf"
    log_path = "/home/user/logs/idle_costs.log"
    assert os.path.isfile(conf_path), f"Logrotate config not found at {conf_path}"

    with open(conf_path, "r", encoding="utf-8") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "/home/user/logs/idle_costs.log" in content, "Target log file missing in logrotate.conf"
    assert "daily" in content, "'daily' missing in logrotate.conf"
    assert "rotate 7" in content, "'rotate 7' missing in logrotate.conf"
    assert "compress" in content, "'compress' missing in logrotate.conf"
    assert "missingok" in content, "'missingok' missing in logrotate.conf"

    env = dict(os.environ, LC_ALL="C")
    debug = subprocess.run(
        ["logrotate", "-d", "-s", "/dev/null", conf_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        env=env,
        text=True,
        timeout=20,
    )
    assert debug.returncode == 0, f"logrotate rejected the configuration:\n{debug.stdout}"
    semantic_pattern = (
        r"rotating pattern:\s*/home/user/logs/idle_costs\.log"
        r"[\s\S]{0,400}?after 1 days \(7 rotations\)"
    )
    assert re.search(semantic_pattern, debug.stdout), (
        "logrotate did not interpret the target as daily with exactly 7 rotations:\n" + debug.stdout
    )

    temp_root = tempfile.mkdtemp(prefix="logrotate-verifier-", dir="/tmp")
    os.chmod(temp_root, 0o777)
    state_path = os.path.join(temp_root, "state")
    saved = []
    try:
        for path in glob.glob(log_path + "*"):
            destination = os.path.join(temp_root, os.path.basename(path))
            shutil.move(path, destination)
            saved.append((path, destination))

        # Force two rotations so compression is observable even if delaycompress
        # was additionally configured.
        for iteration in range(2):
            with open(log_path, "w", encoding="utf-8") as f:
                f.write(f"rotation test {iteration}\n")
            os.chmod(log_path, 0o666)
            result = subprocess.run(
                ["runuser", "-u", "user", "--", "logrotate", "-f", "-s", state_path, conf_path],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=env,
                text=True,
                timeout=20,
            )
            assert result.returncode == 0, f"logrotate configuration is not usable:\n{result.stdout}\n{result.stderr}"

        compressed = glob.glob(log_path + "*.gz")
        assert compressed, "The active logrotate configuration did not compress an old log"
        with gzip.open(compressed[0], "rt", encoding="utf-8") as f:
            assert "rotation test" in f.read(), "Compressed rotation did not contain the test log"

        if os.path.exists(log_path):
            os.remove(log_path)
        missing_state = os.path.join(temp_root, "missing-state")
        missing = subprocess.run(
            ["runuser", "-u", "user", "--", "logrotate", "-s", missing_state, conf_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
            text=True,
            timeout=20,
        )
        assert missing.returncode == 0, "logrotate errored when the target log was missing"
    finally:
        for path in glob.glob(log_path + "*"):
            if os.path.isfile(path) or os.path.islink(path):
                os.remove(path)
            elif os.path.isdir(path):
                shutil.rmtree(path)
        for original, destination in saved:
            if os.path.exists(destination):
                shutil.move(destination, original)
        shutil.rmtree(temp_root, ignore_errors=True)


def test_crontab():
    result = subprocess.run(
        ["crontab", "-l"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert result.returncode == 0, "Failed to read crontab. Has it been created?"

    crontab_content = result.stdout.decode("utf-8")
    pattern = r"^0\s+\*\s+\*\s+\*\s+\*\s+/home/user/run_analysis\.sh"
    match_found = any(re.match(pattern, line.strip()) for line in crontab_content.splitlines())
    assert match_found, f"Crontab does not contain the correct schedule for run_analysis.sh. Crontab content:\n{crontab_content}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
