#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import shutil
import signal
import stat
import subprocess
import time

import pytest
import requests

REF_SOURCE = r'''
#include <stdio.h>
#include <stdlib.h>
#include <omp.h>
int main(int argc, char *argv[]) {
    if (argc != 3) return 1;
    int seed = atoi(argv[1]);
    int threads = atoi(argv[2]);
    omp_set_num_threads(threads);
    long long num_samples = 100000000;
    long long inside_circle = 0;
    #pragma omp parallel reduction(+:inside_circle)
    {
        unsigned int local_seed = seed + omp_get_thread_num();
        #pragma omp for
        for (long long i = 0; i < num_samples; i++) {
            double x = (double)rand_r(&local_seed) / RAND_MAX;
            double y = (double)rand_r(&local_seed) / RAND_MAX;
            if (x * x + y * y <= 1.0) inside_circle++;
        }
    }
    double pi = 4.0 * inside_circle / num_samples;
    printf("%.5f\n", pi);
    return 0;
}
'''

@pytest.fixture(scope="session")
def reference_binary():
    src = "/tmp/mc_sim_ref.c"
    binary = "/tmp/mc_sim_ref"
    with open(src, "w") as f:
        f.write(REF_SOURCE)
    subprocess.run(["gcc", "-O3", "-fopenmp", src, "-o", binary], check=True)
    return binary


def run_program(path, seed, threads):
    result = subprocess.run(
        [path, str(seed), str(threads)],
        capture_output=True, text=True, timeout=40, check=True
    )
    return result.stdout.strip()


def test_mc_sim_compiled_and_behaves_like_openmp_source(reference_binary):
    path = "/home/user/mc_sim"
    assert os.path.isfile(path), "The compiled executable /home/user/mc_sim does not exist."
    assert os.access(path, os.X_OK), "/home/user/mc_sim is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/mc_sim is not a compiled ELF executable."

    linked = subprocess.run(["ldd", path], capture_output=True, text=True, check=True)
    assert "libgomp" in linked.stdout.lower(), "The executable is not linked with OpenMP support."

    # Exercise non-public, varied argument pairs rather than trusting one fixed answer.
    for seed, threads in [(1937, 1), (5271, 2), (9013, 4)]:
        expected = run_program(reference_binary, seed, threads)
        actual = run_program(path, seed, threads)
        assert actual == expected, (
            f"mc_sim output for seed={seed}, threads={threads} was {actual!r}; "
            f"expected {expected!r}."
        )


def listening_addresses(port):
    addresses = []
    for procfile in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(procfile) as f:
                next(f)
                for line in f:
                    cols = line.split()
                    local, state = cols[1], cols[3]
                    host_hex, port_hex = local.rsplit(":", 1)
                    if int(port_hex, 16) == port and state == "0A":
                        addresses.append((procfile, host_hex))
        except FileNotFoundError:
            pass
    return addresses


def test_http_server_response(reference_binary):
    listeners = listening_addresses(8000)
    assert listeners, "No process is listening on port 8000."
    assert ("/proc/net/tcp", "0100007F") in listeners, (
        "The server must listen on IPv4 address 127.0.0.1:8000."
    )
    assert ("/proc/net/tcp", "00000000") not in listeners, (
        "The server is listening on all IPv4 interfaces rather than exactly 127.0.0.1."
    )

    expected_pi = float(run_program(reference_binary, 8842, 4))
    try:
        response = requests.get("http://127.0.0.1:8000/data", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the HTTP server at 127.0.0.1:8000/data: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response body is not valid JSON. Body: {response.text}")

    assert "seed" in data, "JSON response missing 'seed' field."
    assert "pi" in data, "JSON response missing 'pi' field."
    assert "fastest_thread_count" in data, "JSON response missing 'fastest_thread_count' field."
    assert set(data) == {"seed", "pi", "fastest_thread_count"}, "JSON payload has unexpected fields."
    assert data["seed"] == 8842, f"Expected seed 8842, got {data['seed']}"
    assert isinstance(data["fastest_thread_count"], int), "fastest_thread_count must be an integer."
    assert data["fastest_thread_count"] in (1, 2, 4), (
        "fastest_thread_count must be one of the profiled thread counts 1, 2, or 4."
    )
    actual_pi = float(data["pi"])
    assert abs(actual_pi - expected_pi) < 1e-4, f"Expected pi close to {expected_pi}, got {actual_pi}"


def test_profiler_executes_all_runs_captures_results_and_selects_fastest():
    profiler = "/home/user/profiler.sh"
    executable = "/home/user/mc_sim"
    backup = "/tmp/mc_sim.agent-backup"
    log = "/tmp/profiler-invocations.log"

    assert os.path.isfile(profiler), "The required /home/user/profiler.sh does not exist."
    with open(profiler, errors="replace") as f:
        script_text = f.read()
    assert script_text.strip(), "profiler.sh is empty."
    assert re.search(r"(^|\n)\s*#!.*\b(bash|sh)\b", script_text), "profiler.sh is not a shell script."
    assert re.search(r"\b(date|time|SECONDS|EPOCHREALTIME)\b", script_text, re.I), (
        "profiler.sh does not contain a wall-clock timing mechanism."
    )

    fastest = secrets.choice([1, 2, 4])
    delays = {fastest: "0.08"}
    for thread, delay in zip([t for t in (1, 2, 4) if t != fastest], ["0.30", "0.55"]):
        delays[thread] = delay
    values = {1: "3.10101", 2: "3.20202", 4: "3.40404"}

    shutil.copy2(executable, backup)
    try:
        with open(executable, "w") as f:
            f.write("#!/bin/bash\n")
            f.write(f"echo \"$1 $2\" >> {log}\n")
            f.write("case \"$2\" in\n")
            for thread in (1, 2, 4):
                f.write(f"  {thread}) sleep {delays[thread]}; printf '%s\\n' '{values[thread]}' ;;\n")
            f.write("  *) exit 9 ;;\n")
            f.write("esac\n")
        os.chmod(executable, 0o755)
        try:
            os.unlink(log)
        except FileNotFoundError:
            pass

        started = time.time()
        proc = subprocess.Popen(
            ["bash", "-x", profiler], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, start_new_session=True
        )
        try:
            stdout, stderr = proc.communicate(timeout=8)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            stdout, stderr = proc.communicate()
        finally:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except (ProcessLookupError, PermissionError):
                pass

        assert os.path.isfile(log), "profiler.sh never invoked /home/user/mc_sim."
        with open(log) as f:
            calls = [line.split() for line in f if line.strip()]
        for threads in (1, 2, 4):
            assert ["8842", str(threads)] in calls, (
                f"profiler.sh did not run mc_sim with seed 8842 and {threads} thread(s)."
            )

        evidence = stdout + "\n" + stderr
        for root, _, files in os.walk("/home/user"):
            for name in files:
                path = os.path.join(root, name)
                if path in (executable, profiler):
                    continue
                try:
                    st = os.stat(path)
                    if stat.S_ISREG(st.st_mode) and st.st_size <= 262144 and st.st_mtime >= started - 1:
                        with open(path, errors="replace") as f:
                            evidence += "\n" + f.read()
                except (OSError, UnicodeError):
                    pass

        for value in values.values():
            assert value in evidence, f"profiler.sh did not capture the simulated Pi result {value}."
        assert re.search(rf"fastest[^\n]{{0,100}}(?:=|:)\s*{fastest}\b", evidence, re.I), (
            f"With controlled timings, profiler.sh did not identify thread count {fastest} as fastest."
        )
    finally:
        if os.path.exists(backup):
            shutil.copy2(backup, executable)
            os.unlink(backup)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
