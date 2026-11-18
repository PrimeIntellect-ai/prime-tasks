#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'REF_EOF' > /tmp/ref_rolling_cov.cpp
#include <iostream>
#include <vector>
#include <iomanip>
#include <string>
#include <sstream>
using namespace std;
int main() {
    int W;
    if (!(cin >> W)) return 0;
    string line;
    getline(cin, line);
    vector<double> R, G, B;
    while (getline(cin, line)) {
        if (line.empty()) continue;
        stringstream ss(line);
        string token;
        double r=0, g=0, b=0;
        if (getline(ss, token, ',')) r = stod(token);
        if (getline(ss, token, ',')) g = stod(token);
        if (getline(ss, token, ',')) b = stod(token);
        R.push_back(r); G.push_back(g); B.push_back(b);
        if (R.size() >= static_cast<size_t>(W)) {
            int start = static_cast<int>(R.size()) - W;
            double sumR=0, sumG=0, sumB=0;
            for (int i=start; i<static_cast<int>(R.size()); ++i) {
                sumR += R[i]; sumG += G[i]; sumB += B[i];
            }
            double meanR=sumR/W, meanG=sumG/W, meanB=sumB/W;
            double varR=0, varG=0, varB=0, covRG=0, covRB=0, covGB=0;
            for (int i=start; i<static_cast<int>(R.size()); ++i) {
                double dr=R[i]-meanR, dg=G[i]-meanG, db=B[i]-meanB;
                varR += dr*dr; varG += dg*dg; varB += db*db;
                covRG += dr*dg; covRB += dr*db; covGB += dg*db;
            }
            double denom=W-1;
            cout << fixed << setprecision(6)
                 << varR/denom << ',' << varG/denom << ',' << varB/denom << ','
                 << covRG/denom << ',' << covRB/denom << ',' << covGB/denom << '\n';
        }
    }
    return 0;
}
REF_EOF

if ! g++ -O3 /tmp/ref_rolling_cov.cpp -o /tmp/ref_rolling_cov; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import stat
import subprocess
import pytest


def expected_video_features():
    probe = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=width,height", "-of", "csv=p=0:s=x",
         "/app/experiment.mp4"],
        text=True, capture_output=True, check=True
    )
    width, height = map(int, probe.stdout.strip().split("x"))
    decoded = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", "/app/experiment.mp4",
         "-vf", "fps=1", "-pix_fmt", "rgb24", "-f", "rawvideo", "-"],
        capture_output=True, check=True
    ).stdout
    frame_size = width * height * 3
    assert frame_size > 0 and len(decoded) % frame_size == 0
    result = []
    for offset in range(0, len(decoded), frame_size):
        frame = decoded[offset:offset + frame_size]
        pixels = width * height
        result.append((
            sum(frame[0::3]) / pixels,
            sum(frame[1::3]) / pixels,
            sum(frame[2::3]) / pixels,
        ))
    return result


def test_video_features_csv_exists_and_format():
    csv_path = "/home/user/video_features.csv"
    assert os.path.exists(csv_path), f"Missing required file: {csv_path}"

    with open(csv_path, "r") as f:
        lines = f.read().strip().split("\n")

    assert len(lines) > 1, f"CSV {csv_path} has no data lines."
    assert lines[0].strip() == "frame,R_avg,G_avg,B_avg", \
        f"Incorrect headers in {csv_path}. Expected 'frame,R_avg,G_avg,B_avg', got '{lines[0]}'"

    parsed = []
    for i, line in enumerate(lines[1:], start=2):
        parts = line.split(',')
        assert len(parts) == 4, \
            f"Line {i} in {csv_path} does not have exactly 4 columns: {line}"
        try:
            frame_number = float(parts[0])
            rgb = tuple(float(value) for value in parts[1:])
        except ValueError:
            pytest.fail(f"Line {i} contains non-numeric data: {line}")
        assert math.isfinite(frame_number) and frame_number.is_integer(), \
            f"Line {i} has an invalid frame number: {parts[0]}"
        assert all(math.isfinite(value) for value in rgb), \
            f"Line {i} has a non-finite RGB value: {line}"
        parsed.append((int(frame_number), rgb))

    expected = expected_video_features()
    assert len(parsed) == len(expected), \
        f"Expected {len(expected)} frames at 1 fps, but CSV contains {len(parsed)} rows"

    frame_ids = [row[0] for row in parsed]
    assert frame_ids in (list(range(len(parsed))), list(range(1, len(parsed) + 1))), \
        f"Frame numbers must be consecutive and start at 0 or 1; got {frame_ids}"

    for index, ((_, actual), wanted) in enumerate(zip(parsed, expected)):
        for channel, actual_value, expected_value in zip("RGB", actual, wanted):
            assert abs(actual_value - expected_value) <= 0.01, \
                f"Frame {index} {channel} average is {actual_value}, expected {expected_value:.6f}"


def test_rolling_cov_fuzz_equivalence():
    agent_source = "/home/user/rolling_cov.cpp"
    agent_bin = "/home/user/rolling_cov"
    rebuilt_bin = "/tmp/rebuilt_rolling_cov"
    ref_bin = "/tmp/ref_rolling_cov"

    assert os.path.exists(agent_source), f"Agent source not found at {agent_source}"
    assert os.path.isfile(agent_source) and not os.path.islink(agent_source), \
        f"Agent source must be a regular file: {agent_source}"
    assert os.path.exists(agent_bin), f"Agent binary not found at {agent_bin}"
    assert os.access(agent_bin, os.X_OK), f"Agent binary is not executable: {agent_bin}"
    assert stat.S_ISREG(os.stat(agent_bin).st_mode), f"Agent binary is not a regular executable file: {agent_bin}"
    assert os.path.exists(ref_bin), f"Reference binary not found at {ref_bin}"

    build = subprocess.run(
        ["g++", "-O3", agent_source, "-o", rebuilt_bin],
        text=True, capture_output=True
    )
    assert build.returncode == 0, f"Agent C++ source failed to compile: {build.stderr}"

    random.seed(42)
    N_RUNS = 1000

    for i in range(N_RUNS):
        W = random.randint(2, 100)
        L = random.randint(W, W + 500)
        input_lines = [str(W)]
        for _ in range(L):
            r = random.uniform(0.0, 255.0)
            g = random.uniform(0.0, 255.0)
            b = random.uniform(0.0, 255.0)
            input_lines.append(f"{r:.6f},{g:.6f},{b:.6f}")
        input_data = "\n".join(input_lines) + "\n"

        ref_proc = subprocess.run([ref_bin], input=input_data, text=True, capture_output=True)
        agent_proc = subprocess.run([agent_bin], input=input_data, text=True, capture_output=True)
        rebuilt_proc = subprocess.run([rebuilt_bin], input=input_data, text=True, capture_output=True)

        assert ref_proc.returncode == 0, f"Reference binary failed on run {i}"
        assert agent_proc.returncode == 0, \
            f"Agent binary failed on run {i} with error: {agent_proc.stderr}"
        assert rebuilt_proc.returncode == 0, \
            f"Compiled agent source failed on run {i} with error: {rebuilt_proc.stderr}"

        for artifact, output in (("agent binary", agent_proc.stdout),
                                 ("compiled agent source", rebuilt_proc.stdout)):
            if output != ref_proc.stdout:
                ref_out = ref_proc.stdout
                agent_out = output
                if len(ref_out) > 500:
                    ref_out = ref_out[:500] + "\n...[truncated]"
                if len(agent_out) > 500:
                    agent_out = agent_out[:500] + "\n...[truncated]"
                pytest.fail(
                    f"Mismatch from {artifact} on fuzz run {i}.\n"
                    f"Input parameters: W={W}, L={L}\n"
                    f"--- Reference Output (first 500 chars) ---\n{ref_out}\n"
                    f"--- Agent Output (first 500 chars) ---\n{agent_out}\n"
                )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
