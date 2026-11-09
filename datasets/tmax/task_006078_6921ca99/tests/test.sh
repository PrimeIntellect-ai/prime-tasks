#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import math
import pwd
import stat
import time
import shutil
import secrets
import subprocess
import tempfile

import numpy as np


def test_cpp_source_fixed():
    path = "/home/user/pi_sim.cpp"
    assert os.path.isfile(path), f"File not found: {path}"
    with open(path, "r") as f:
        code = f.read()

    # Preserve the original source assertions.
    assert "atomic" not in code, "The atomic pragma was not removed from pi_sim.cpp"
    assert "reduction" in code, "OpenMP reduction clause not found in pi_sim.cpp"
    assert "+:sum" in code.replace(" ", ""), "Reduction clause does not correctly specify +:sum"

    # The requested workload and loop bound must remain intact.
    compact = re.sub(r"\s+", "", code)
    assert re.search(r"(?:long|int64_t|longlong)num_steps=50000000[;UL]*", compact), \
        "num_steps must remain 50000000"
    assert re.search(r"for\([^;]*;[^;]*<num_steps;", compact), \
        "The integration loop must still run to num_steps"
    assert re.search(r"#pragma\s+omp\s+parallel\s+for[^\n]*reduction\s*\(\s*\+\s*:\s*sum\s*\)", code), \
        "The parallel loop must use an OpenMP + reduction on sum"

    # Compile the submitted source with the required compiler flags and execute it.
    built = "/tmp/pi_sim_verifier_build"
    cp = subprocess.run(
        ["g++", "-O3", "-fopenmp", path, "-o", built],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60
    )
    assert cp.returncode == 0, f"pi_sim.cpp does not compile with -O3 -fopenmp:\n{cp.stderr}"
    env = os.environ.copy()
    env["OMP_NUM_THREADS"] = "2"
    start = time.monotonic()
    run = subprocess.run([built], text=True, stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE, env=env, timeout=45)
    wall_ms = (time.monotonic() - start) * 1000.0
    assert run.returncode == 0, f"Compiled simulation failed: {run.stderr}"
    m = re.fullmatch(r"\s*Pi:\s*([-+0-9.eE]+),\s*Time:\s*([-+0-9.eE]+)\s*", run.stdout)
    assert m, f"Unexpected simulation output: {run.stdout!r}"
    pi_value, reported_ms = map(float, m.groups())
    assert math.isfinite(pi_value) and abs(pi_value - math.pi) < 1e-8, \
        f"Simulation produced an incorrect pi value: {pi_value}"
    assert math.isfinite(reported_ms) and reported_ms > 0, "Reported time must be positive and finite"
    assert reported_ms <= wall_ms * 5 + 10 and reported_ms >= wall_ms * 0.02, \
        "Reported execution time is inconsistent with the observed computation"


def test_cpp_executable_exists():
    path = "/home/user/pi_sim"
    assert os.path.isfile(path), f"Executable not found: {path}"
    assert os.access(path, os.X_OK), f"File is not executable: {path}"
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "pi_sim is not a compiled executable"

    env = os.environ.copy()
    env["OMP_NUM_THREADS"] = "2"
    result = subprocess.run([path], text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, env=env, timeout=45)
    assert result.returncode == 0, f"Submitted executable failed: {result.stderr}"
    m = re.fullmatch(r"\s*Pi:\s*([-+0-9.eE]+),\s*Time:\s*([-+0-9.eE]+)\s*", result.stdout)
    assert m, f"Submitted executable has incorrect output: {result.stdout!r}"
    assert abs(float(m.group(1)) - math.pi) < 1e-8
    assert math.isfinite(float(m.group(2))) and float(m.group(2)) > 0


def test_bash_script_exists():
    path = "/home/user/run_experiments.sh"
    assert os.path.isfile(path), f"Bash script not found: {path}"


def test_times_csv_created():
    path = "/home/user/times.csv"
    assert os.path.isfile(path), f"CSV file not found: {path}"
    with open(path, "r") as f:
        lines = f.read().strip().split("\n")

    assert len(lines) == 100, f"times.csv has {len(lines)} lines, expected exactly 100"
    for line in lines:
        try:
            value = float(line)
        except ValueError:
            assert False, f"Line in times.csv is not a valid float: '{line}'"
        assert math.isfinite(value) and value > 0, f"Invalid execution time: '{line}'"


def test_python_script_exists():
    path = "/home/user/analyze.py"
    assert os.path.isfile(path), f"Python script not found: {path}"


def test_ci_txt_created():
    path = "/home/user/ci.txt"
    assert os.path.isfile(path), f"ci.txt not found: {path}"
    with open(path, "r") as f:
        content = f.read().strip()

    match = re.match(r'^\d+\.\d+,\d+\.\d+$', content)
    assert match, f"ci.txt format incorrect, expected 'float,float' but got: '{content}'"


def test_histogram_png_created():
    path = "/home/user/histogram.png"
    assert os.path.isfile(path), f"histogram.png not found: {path}"
    with open(path, "rb") as f:
        header = f.read(8)
    assert header == b'\x89PNG\r\n\x1a\n', f"File is not a valid PNG image: {path}"


def _demote_to_user():
    account = pwd.getpwnam("user")
    os.setgroups([])
    os.setgid(account.pw_gid)
    os.setuid(account.pw_uid)


def test_z_scripts_are_executed_and_correct():
    user = pwd.getpwnam("user")
    binary = "/home/user/pi_sim"
    script = "/home/user/run_experiments.sh"
    analyze = "/home/user/analyze.py"

    # Replace pi_sim temporarily with a protected probe. This checks that the bash
    # script invokes it exactly 100 times and records exactly the reported times.
    private = tempfile.mkdtemp(prefix="experiment_probe_", dir="/tmp")
    os.chmod(private, 0o700)
    saved_binary = os.path.join(private, "real_pi_sim")
    counter = os.path.join(private, "counter")
    probe_src = os.path.join(private, "probe.c")
    shutil.move(binary, saved_binary)
    old_home_mode = stat.S_IMODE(os.stat("/home/user").st_mode)
    try:
        escaped_counter = counter.replace('\\', '\\\\').replace('"', '\\"')
        with open(probe_src, "w") as f:
            f.write(r'''#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <stdlib.h>
int main(void) {
    if (setuid(0) != 0) return 91;
    int fd = open("''' + escaped_counter + r'''", O_RDWR|O_CREAT, 0600);
    if (fd < 0 || flock(fd, LOCK_EX) != 0) return 92;
    char buf[64] = {0};
    int n = 0;
    ssize_t got = read(fd, buf, sizeof(buf)-1);
    if (got > 0) n = atoi(buf);
    n++;
    snprintf(buf, sizeof(buf), "%d\n", n);
    lseek(fd, 0, SEEK_SET);
    ftruncate(fd, 0);
    if (write(fd, buf, strlen(buf)) < 0) return 93;
    flock(fd, LOCK_UN);
    close(fd);
    printf("Pi: 3.141592654, Time: %.6f\n", 17.125 + n * 0.013);
    return 0;
}
''')
        cc = subprocess.run(["gcc", probe_src, "-O2", "-o", binary],
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert cc.returncode == 0, cc.stderr
        os.chown(binary, 0, 0)
        os.chmod(binary, 0o4755)
        os.chmod("/home/user", 0o1777)

        if os.path.lexists("/home/user/times.csv"):
            os.unlink("/home/user/times.csv")
        env = os.environ.copy()
        env["HOME"] = "/home/user"
        run = subprocess.run(["/bin/bash", script], cwd="/home/user", env=env,
                             text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                             preexec_fn=_demote_to_user, timeout=120)
        assert run.returncode == 0, f"run_experiments.sh failed:\n{run.stderr}"
        with open(counter) as f:
            calls = int(f.read().strip())
        assert calls == 100, f"run_experiments.sh invoked pi_sim {calls} times, expected exactly 100"
        with open("/home/user/times.csv") as f:
            rows = f.read().strip().splitlines()
        assert len(rows) == 100, f"Experiment script wrote {len(rows)} values, expected 100"
        actual = [float(x) for x in rows]
        expected = [17.125 + n * 0.013 for n in range(1, 101)]
        assert np.allclose(actual, expected, rtol=0, atol=5e-7), \
            "times.csv does not contain the time value extracted from every program run"
    finally:
        if os.path.lexists(binary):
            os.unlink(binary)
        if os.path.exists(saved_binary):
            shutil.move(saved_binary, binary)
        os.chmod("/home/user", old_home_mode)

    # Give analyze.py verifier-generated, nonconstant data unknown before this run.
    rng = secrets.SystemRandom()
    data = np.array([5.0 + rng.random() * 12.0 + (18.0 if i % 17 == 0 else 0.0)
                     for i in range(100)], dtype=float)
    with open("/home/user/times.csv", "w") as f:
        for value in data:
            f.write(f"{value:.9f}\n")
    os.chown("/home/user/times.csv", user.pw_uid, user.pw_gid)
    for output in ("/home/user/ci.txt", "/home/user/histogram.png"):
        if os.path.lexists(output):
            os.unlink(output)

    env = os.environ.copy()
    env["HOME"] = "/home/user"
    env["MPLBACKEND"] = "Agg"
    result = subprocess.run(["python3", analyze], cwd="/home/user", env=env,
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            preexec_fn=_demote_to_user, timeout=120)
    assert result.returncode == 0, f"analyze.py failed:\n{result.stderr}"

    # Independently reproduce the specified 10,000-resample, seed-42 percentile CI.
    recorded = np.loadtxt("/home/user/times.csv")
    bootstrap_rng = np.random.RandomState(42)
    means = np.empty(10000)
    for i in range(10000):
        means[i] = np.mean(bootstrap_rng.choice(recorded, size=100, replace=True))
    lower, upper = np.percentile(means, [2.5, 97.5])
    expected_ci = f"{lower:.3f},{upper:.3f}"
    with open("/home/user/ci.txt") as f:
        actual_ci = f.read().strip()
    assert actual_ci == expected_ci, \
        f"Incorrect bootstrap CI: got {actual_ci!r}, expected {expected_ci!r}"

    # Require a decodable, nonempty plot produced by the analysis execution.
    histogram = "/home/user/histogram.png"
    assert os.path.isfile(histogram) and os.path.getsize(histogram) > 1000
    import matplotlib.image as mpimg
    image = mpimg.imread(histogram)
    assert image.ndim in (2, 3) and image.shape[0] >= 100 and image.shape[1] >= 100
    assert float(np.nanstd(image)) > 0.01, "histogram.png is blank or contains no plotted content"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
