#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import tempfile
import pytest


def get_ground_truth():
    """
    Compiles and runs the reference C++ implementation to compute
    the exact expected threshold, clean record count, and clean data.
    """
    cpp_code = r"""
    #include <iostream>
    #include <fstream>
    #include <vector>
    #include <random>
    #include <algorithm>
    #include <iomanip>

    using namespace std;

    int main(int argc, char** argv) {
        if (argc != 2) return 2;

        vector<float> raw_data(100000 * 10);
        ifstream fd("/home/user/data/raw_data.bin", ios::binary);
        if (!fd) return 1;
        fd.read((char*)raw_data.data(), 100000 * 10 * sizeof(float));

        vector<float> W_enc(5 * 10), W_dec(10 * 5), bias(10);
        ifstream fwe("/home/user/data/encoder_weights.bin", ios::binary);
        fwe.read((char*)W_enc.data(), 50 * sizeof(float));
        ifstream fwd("/home/user/data/decoder_weights.bin", ios::binary);
        fwd.read((char*)W_dec.data(), 50 * sizeof(float));
        ifstream fb("/home/user/data/bias.bin", ios::binary);
        fb.read((char*)bias.data(), 10 * sizeof(float));

        vector<float> errors(100000);
        for (int i = 0; i < 100000; ++i) {
            float x[10], h[5] = {0}, x_hat[10] = {0};
            for (int j = 0; j < 10; ++j) x[j] = raw_data[i * 10 + j];

            for (int r = 0; r < 5; ++r)
                for (int c = 0; c < 10; ++c)
                    h[r] += W_enc[r * 10 + c] * x[c];

            for (int r = 0; r < 10; ++r) {
                float sum = 0;
                for (int c = 0; c < 5; ++c)
                    sum += W_dec[r * 5 + c] * h[c];
                x_hat[r] = sum + bias[r];
            }

            float err = 0;
            for (int j = 0; j < 10; ++j)
                err += (x[j] - x_hat[j]) * (x[j] - x_hat[j]);
            errors[i] = err;
        }

        mt19937 gen(42);
        uniform_int_distribution<int> dist(0, 99999);

        double sum_p95 = 0;
        for (int i = 0; i < 1000; ++i) {
            vector<float> sample(10000);
            for (int j = 0; j < 10000; ++j) {
                sample[j] = errors[dist(gen)];
            }
            sort(sample.begin(), sample.end());
            sum_p95 += sample[9500];
        }

        float T = sum_p95 / 1000.0;

        ofstream clean(argv[1], ios::binary);
        if (!clean) return 3;

        int clean_count = 0;
        for (int i = 0; i < 100000; ++i) {
            if (errors[i] <= T) {
                clean.write((char*)&raw_data[i * 10], 10 * sizeof(float));
                clean_count++;
            }
        }
        if (!clean) return 4;

        cout << fixed << setprecision(4) << T << endl;
        cout << clean_count << endl;
        return 0;
    }
    """
    with tempfile.TemporaryDirectory() as tmpdir:
        src = os.path.join(tmpdir, "truth.cpp")
        exe = os.path.join(tmpdir, "truth")
        expected_clean_path = os.path.join(tmpdir, "expected_clean_data.bin")
        with open(src, "w") as f:
            f.write(cpp_code)

        try:
            subprocess.run(["g++", "-O3", src, "-o", exe], check=True, capture_output=True)
            res = subprocess.run(
                [exe, expected_clean_path], capture_output=True, text=True, check=True
            )
            lines = res.stdout.strip().split("\n")
            with open(expected_clean_path, "rb") as f:
                expected_clean_data = f.read()
            return lines[0], int(lines[1]), expected_clean_data
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Failed to compute ground truth: {e.stderr}")


@pytest.fixture(scope="module")
def truth_data():
    return get_ground_truth()


def test_summary_txt_exists_and_correct(truth_data):
    """Test that summary.txt exists and contains the correct threshold and count."""
    expected_t, expected_count, _ = truth_data
    summary_path = "/home/user/data/summary.txt"

    assert os.path.isfile(summary_path), f"File {summary_path} is missing."

    with open(summary_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 lines in summary.txt, got {len(lines)}."

    actual_t = lines[0]
    actual_count = lines[1]

    assert actual_t == expected_t, f"Line 1 (Threshold) mismatch. Expected '{expected_t}', got '{actual_t}'."
    assert actual_count == str(expected_count), f"Line 2 (Clean count) mismatch. Expected '{expected_count}', got '{actual_count}'."


def test_clean_data_bin_exists_and_size(truth_data):
    """Test that clean_data.bin has the correct size and exact filtered records."""
    _, expected_count, expected_clean_data = truth_data
    clean_data_path = "/home/user/data/clean_data.bin"

    assert os.path.isfile(clean_data_path), f"File {clean_data_path} is missing."

    expected_size = expected_count * 10 * 4  # count * 10 floats * 4 bytes
    actual_size = os.path.getsize(clean_data_path)

    assert actual_size == expected_size, f"File {clean_data_path} size mismatch. Expected {expected_size} bytes, got {actual_size} bytes."

    with open(clean_data_path, "rb") as f:
        actual_clean_data = f.read()

    assert actual_clean_data == expected_clean_data, \
        f"File {clean_data_path} does not contain the expected filtered original records in order."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
