#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import json
import os
import random
import secrets
import signal
import subprocess
import tempfile
import time
from pathlib import Path

import pytest

REF_CPP = r'''
#include <cctype>
#include <fstream>
#include <functional>
#include <sstream>
#include <string>
using namespace std;

bool is_valid_numeric(const string& s) {
    if (s.empty()) return false;
    size_t start = 0;
    if (s[0] == '-') start = 1;
    if (start == s.length()) return false;
    bool has_dot = false;
    bool has_digit = false;
    for (size_t i = start; i < s.length(); ++i) {
        if (s[i] == '.') {
            if (has_dot) return false;
            has_dot = true;
        } else if (isdigit(static_cast<unsigned char>(s[i]))) {
            has_digit = true;
        } else {
            return false;
        }
    }
    return has_digit;
}

int main(int argc, char** argv) {
    if (argc != 3) return 1;
    ifstream in(argv[1]);
    ofstream out(argv[2]);
    if (!in || !out) return 1;
    string line;
    const string salt = "z9X_#Lq2";
    while (getline(in, line)) {
        if (line.empty()) continue;
        stringstream ss(line);
        string ts, temp, volt, rpm;
        if (!getline(ss, ts, ',')) continue;
        if (!getline(ss, temp, ',')) continue;
        if (!getline(ss, volt, ',')) continue;
        if (!getline(ss, rpm, ',')) continue;
        if (!rpm.empty() && rpm.back() == '\r') rpm.pop_back();
        if (!is_valid_numeric(temp) || !is_valid_numeric(volt) || !is_valid_numeric(rpm)) continue;
        auto write_row = [&](const string& sensor, const string& value) {
            string key = ts + "_" + sensor + "_" + value + "_" + salt;
            out << ts << ',' << sensor << ',' << value << ','
                << hash<string>{}(key) << '\n';
        };
        write_row("temp", temp);
        write_row("volt", volt);
        write_row("rpm", rpm);
    }
    return 0;
}
'''

@pytest.fixture(scope="session")
def ref_bin(tmp_path_factory):
    build = tmp_path_factory.mktemp("reference_build")
    source = build / "reference.cpp"
    binary = build / "reference"
    source.write_text(REF_CPP)
    subprocess.run(["g++", "-O2", "-std=c++17", str(source), "-o", str(binary)], check=True)
    return str(binary)


def compare_with_reference(ref_bin, input_path, workdir):
    token = secrets.token_hex(8)
    ref_out = Path(workdir) / ("ref_" + token + ".csv")
    stu_out = Path(workdir) / ("stu_" + token + ".csv")
    subprocess.run([ref_bin, str(input_path), str(ref_out)], check=True)
    result = subprocess.run(
        ["/home/user/cleaner", str(input_path), str(stu_out)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    assert stu_out.is_file(), "Cleaner did not create its requested output file"
    assert stu_out.read_bytes() == ref_out.read_bytes()


def test_cleaner_binary_exists():
    binary_path = "/home/user/cleaner"
    assert os.path.isfile(binary_path), f"Cleaner binary not found at {binary_path}"
    assert os.access(binary_path, os.X_OK), f"Cleaner binary at {binary_path} is not executable"
    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Cleaner must be a compiled executable"


def test_process_all_script_exists():
    script_path = "/home/user/process_all.sh"
    assert os.path.isfile(script_path), f"Script not found at {script_path}"
    assert os.access(script_path, os.X_OK), f"Script at {script_path} is not executable"


def test_clean_corpus_preserved(ref_bin, tmp_path):
    clean_dir = "/app/corpus/clean"
    student_bin = "/home/user/cleaner"
    assert os.path.isdir(clean_dir), f"Clean corpus directory missing: {clean_dir}"
    failed_files = []
    total_files = 0
    for fname in os.listdir(clean_dir):
        if not fname.endswith(".csv"):
            continue
        total_files += 1
        in_path = os.path.join(clean_dir, fname)
        ref_out = tmp_path / ("ref_clean_" + fname)
        stu_out = tmp_path / ("stu_clean_" + fname)
        subprocess.run([ref_bin, in_path, str(ref_out)], check=True)
        result = subprocess.run([student_bin, in_path, str(stu_out)], capture_output=True)
        if result.returncode != 0 or not stu_out.exists():
            failed_files.append(fname)
            continue
        if ref_out.read_text().strip() != stu_out.read_text().strip():
            failed_files.append(fname)
    assert not failed_files, f"{len(failed_files)} of {total_files} clean files modified incorrectly: {failed_files}"


def test_evil_corpus_rejected(ref_bin, tmp_path):
    evil_dir = "/app/corpus/evil"
    student_bin = "/home/user/cleaner"
    assert os.path.isdir(evil_dir), f"Evil corpus directory missing: {evil_dir}"
    failed_files = []
    total_files = 0
    for fname in os.listdir(evil_dir):
        if not fname.endswith(".csv"):
            continue
        total_files += 1
        in_path = os.path.join(evil_dir, fname)
        ref_out = tmp_path / ("ref_evil_" + fname)
        stu_out = tmp_path / ("stu_evil_" + fname)
        subprocess.run([ref_bin, in_path, str(ref_out)], check=True)
        result = subprocess.run([student_bin, in_path, str(stu_out)], capture_output=True)
        if result.returncode != 0 or not stu_out.exists():
            failed_files.append(fname)
            continue
        if ref_out.read_text().strip() != stu_out.read_text().strip():
            failed_files.append(fname)
    assert not failed_files, f"{len(failed_files)} of {total_files} evil files bypassed validation: {failed_files}"


def random_valid_number(rng):
    n = str(rng.randint(0, 999999))
    forms = [n, "-" + n, n + "." + str(rng.randint(0, 9999)),
             "-" + n + "." + str(rng.randint(0, 9999)),
             "." + str(rng.randint(1, 9999)), n + "."]
    return rng.choice(forms)


def test_randomized_adversarial_inputs(ref_bin, tmp_path):
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    bad_values = [
        "NaN", "+12", "--7", "1.2.3", "1e5", "-", ".", " 12",
        "12 ", "0x10", "1;DROP_" + secrets.token_hex(5),
        "7OR" + secrets.token_hex(4), "9/2", "3'", "4_5", ""
    ]
    for case_no in range(6):
        rows = []
        for _ in range(rng.randint(5, 10)):
            ts = str(rng.randint(1000000000, 9999999999))
            rows.append([ts, random_valid_number(rng), random_valid_number(rng), random_valid_number(rng)])
        for bad in bad_values:
            ts = str(rng.randint(1000000000, 9999999999))
            values = [random_valid_number(rng), random_valid_number(rng), random_valid_number(rng)]
            values[rng.randrange(3)] = bad
            rows.append([ts] + values)
        rng.shuffle(rows)
        input_path = tmp_path / ("generated_" + secrets.token_hex(10) + ".csv")
        newline = "\r\n" if case_no % 2 else "\n"
        content = newline.join(["timestamp,temp,volt,rpm"] + [",".join(r) for r in rows]) + newline
        input_path.write_bytes(content.encode())
        compare_with_reference(ref_bin, input_path, tmp_path)


def test_process_all_finds_files_and_runs_in_parallel(ref_bin, tmp_path):
    input_dir = tmp_path / ("inputs_" + secrets.token_hex(6))
    output_dir = tmp_path / ("outputs_" + secrets.token_hex(6))
    input_dir.mkdir()
    output_dir.mkdir()
    inputs = []
    for i in range(4):
        path = input_dir / ("batch_" + secrets.token_hex(6) + ".csv")
        path.write_text(
            "timestamp,temp,volt,rpm\n"
            + f"{random.randint(1000000,9999999)},{20+i}.5,-{i}.25,{3000+i}\n"
        )
        inputs.append(path)
    (input_dir / "ignore.txt").write_text("not a csv")

    cleaner = Path("/home/user/cleaner")
    real_cleaner = Path("/home/user/cleaner.verifier-real")
    state_dir = tmp_path / ("parallel_state_" + secrets.token_hex(6))
    state_dir.mkdir()
    lock_path = state_dir / "lock"
    count_path = state_dir / "count"
    max_path = state_dir / "max"
    log_path = state_dir / "calls.jsonl"
    count_path.write_text("0")
    max_path.write_text("0")

    shim = f'''#!/usr/bin/python3
import fcntl, json, subprocess, sys, time
lock_path = {str(lock_path)!r}
count_path = {str(count_path)!r}
max_path = {str(max_path)!r}
log_path = {str(log_path)!r}
real = {str(real_cleaner)!r}
def update(delta):
    with open(lock_path, "a+") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            with open(count_path) as f: count = int(f.read() or "0")
            count += delta
            with open(count_path, "w") as f: f.write(str(count))
            with open(max_path) as f: maximum = int(f.read() or "0")
            if count > maximum:
                with open(max_path, "w") as f: f.write(str(count))
            return count
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)
with open(lock_path, "a+") as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    with open(log_path, "a") as log:
        log.write(json.dumps(sys.argv[1:]) + "\\n")
    fcntl.flock(lock, fcntl.LOCK_UN)
update(1)
try:
    time.sleep(0.7)
    result = subprocess.run([real] + sys.argv[1:])
    sys.exit(result.returncode)
finally:
    update(-1)
'''

    proc = None
    os.replace(cleaner, real_cleaner)
    try:
        cleaner.write_text(shim)
        cleaner.chmod(0o755)
        proc = subprocess.Popen(
            ["/home/user/process_all.sh", str(input_dir), str(output_dir)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            start_new_session=True,
        )
        try:
            stdout, stderr = proc.communicate(timeout=20)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.communicate()
            pytest.fail("process_all.sh did not finish")
        time.sleep(0.2)
        assert proc.returncode == 0, stderr.decode(errors="replace")
        assert int(count_path.read_text()) == 0, "process_all.sh returned before its workers finished"
    finally:
        if proc is not None:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        try:
            cleaner.unlink()
        except FileNotFoundError:
            pass
        if real_cleaner.exists():
            os.replace(real_cleaner, cleaner)

    calls = []
    if log_path.exists():
        calls = [json.loads(line) for line in log_path.read_text().splitlines() if line]
    assert len(calls) == len(inputs), "process_all.sh must invoke cleaner once for every .csv file"
    assert all(len(call) == 2 for call in calls), "Each cleaner invocation needs input and output paths"
    called_inputs = [os.path.realpath(call[0]) for call in calls]
    assert sorted(called_inputs) == sorted(os.path.realpath(str(p)) for p in inputs)
    assert int(max_path.read_text()) >= 2, "CSV files were processed sequentially rather than in parallel"

    for call in calls:
        source, produced = call
        produced_real = os.path.realpath(produced)
        assert os.path.commonpath([produced_real, os.path.realpath(output_dir)]) == os.path.realpath(output_dir), \
            "Wrapper output paths must be inside the requested output directory"
        assert os.path.isfile(produced), f"Missing wrapper output for {source}"
        expected = tmp_path / ("wrapper_ref_" + secrets.token_hex(6) + ".csv")
        subprocess.run([ref_bin, source, str(expected)], check=True)
        assert Path(produced).read_bytes() == expected.read_bytes()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
