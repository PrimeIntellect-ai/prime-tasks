#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import signal
import subprocess
import time
import pytest

MC = "/home/user/mc_volume.sh"
CONV = "/home/user/convergence.sh"
RESULT = "/home/user/convergence_result.txt"
NUMBER_RE = re.compile(r"^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$")


def run_volume(args, timeout=20):
    result = subprocess.run([MC, *map(str, args)], capture_output=True, text=True, timeout=timeout)
    assert result.returncode == 0, f"mc_volume.sh failed for {args}: {result.stderr}"
    output = result.stdout.strip()
    assert NUMBER_RE.fullmatch(output), f"mc_volume.sh must print only one decimal number; got {output!r}"
    value = float(output)
    assert math.isfinite(value), f"mc_volume.sh returned a non-finite value: {output}"
    return value


def true_volume(d, r):
    return (math.pi ** (d / 2.0) / math.gamma(d / 2.0 + 1.0)) * (r ** d)


def test_scripts_exist_and_executable():
    for path in (MC, CONV):
        assert os.path.exists(path), f"{path} does not exist."
        assert os.path.isfile(path), f"{path} is not a regular file."
        assert os.access(path, os.X_OK), f"{path} is not executable."


def test_mc_uses_awk_random_sampling_and_parallel_jobs():
    source = open(MC, encoding="utf-8", errors="replace").read()
    assert re.search(r"\bawk\b", source), "mc_volume.sh must use awk for sampling."
    assert re.search(r"\brand\s*\(", source), "The awk sampling must generate random coordinates with rand()."
    assert re.search(r"\bsrand\s*\(", source), "Each awk sampler must initialize a random seed."
    has_background_jobs = re.search(r"(?<!&)&(?!&)", source) and re.search(r"\bwait\b", source)
    has_xargs_parallel = re.search(r"\bxargs\b[^\n]*\s-P(?:\s|[0-9$])", source)
    assert has_background_jobs or has_xargs_parallel, "Sampling must use background jobs with wait or xargs -P."


def test_mc_requires_exactly_four_arguments():
    for args in (["3", "1", "1000"], ["3", "1", "1000", "4", "extra"]):
        result = subprocess.run([MC, *args], capture_output=True, text=True, timeout=5)
        assert result.returncode != 0, f"mc_volume.sh must reject {len(args)} arguments."


def test_mc_volume_execution():
    # Preserve the original fixed numerical assertion.
    vol = run_volume([4, "1.0", 100000, 4], timeout=10)
    expected_vol = 4.9348
    assert abs(vol - expected_vol) <= 0.5, f"mc_volume.sh returned {vol}, expected roughly {expected_vol}."


def test_mc_volume_on_unpredictable_inputs():
    # Inputs are selected at verification time, and expected answers are derived here.
    rng = random.SystemRandom()
    dimensions = rng.sample([2, 3, 4, 5, 6], 3)
    radii = [rng.choice([0.65, 0.9, 1.25, 1.7, 2.1]) for _ in dimensions]
    processes = [rng.choice([2, 3, 4]) for _ in dimensions]

    for d, r, p in zip(dimensions, radii, processes):
        n = p * rng.choice([10000, 12000, 15000])
        observed = run_volume([d, r, n, p])
        expected = true_volume(d, r)
        box = (2.0 * r) ** d
        probability = expected / box
        sigma = box * math.sqrt(probability * (1.0 - probability) / n)
        tolerance = max(8.0 * sigma, 0.04 * expected)
        assert abs(observed - expected) <= tolerance, (
            f"For D={d}, R={r}, N={n}, P={p}, got {observed}; "
            f"expected {expected} within Monte Carlo tolerance {tolerance}."
        )


def descendant_pids(root_pid):
    parents = {}
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            with open(f"/proc/{name}/status") as f:
                status = f.read()
            match = re.search(r"^PPid:\s+(\d+)$", status, re.MULTILINE)
            if match:
                parents[int(name)] = int(match.group(1))
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass

    descendants = set()
    frontier = {root_pid}
    while frontier:
        new = {pid for pid, ppid in parents.items() if ppid in frontier and pid not in descendants}
        descendants.update(new)
        frontier = new
    return descendants


def test_parallel_awk_processes_are_actually_run():
    proc = subprocess.Popen(
        [MC, "3", "1.0", "800000", "4"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    max_concurrent_awk = 0
    deadline = time.time() + 20
    try:
        while proc.poll() is None and time.time() < deadline:
            count = 0
            for pid in descendant_pids(proc.pid):
                try:
                    comm = open(f"/proc/{pid}/comm").read().strip()
                    if comm in {"awk", "gawk", "mawk", "nawk"}:
                        count += 1
                except (FileNotFoundError, ProcessLookupError, PermissionError):
                    pass
            max_concurrent_awk = max(max_concurrent_awk, count)
            time.sleep(0.003)

        if proc.poll() is None:
            os.killpg(proc.pid, signal.SIGKILL)
            pytest.fail("mc_volume.sh did not finish the parallel sampling test within 20 seconds.")
        stdout, stderr = proc.communicate()
    finally:
        if proc.poll() is None:
            os.killpg(proc.pid, signal.SIGKILL)

    assert proc.returncode == 0, f"Parallel execution failed: {stderr}"
    assert NUMBER_RE.fullmatch(stdout.strip()), f"Invalid output from parallel execution: {stdout!r}"
    assert max_concurrent_awk >= 2, "No concurrently running awk sampling processes were observed."
    assert abs(float(stdout.strip()) - true_volume(3, 1.0)) <= 0.25


def parse_result_file():
    assert os.path.exists(RESULT), f"{RESULT} does not exist."
    content = open(RESULT).read().strip()
    match = re.fullmatch(r"N:\s+(\d+),\s+Volume:\s+(\d+(?:\.\d+)?)", content)
    assert match, f"Content of {RESULT} does not match 'N: <N>, Volume: <Vol>'. Got: {content}"
    return int(match.group(1)), float(match.group(2))


def test_convergence_is_executed_and_result_is_reasonable():
    # Remove any prewritten result and execute the submitted convergence script.
    try:
        os.unlink(RESULT)
    except FileNotFoundError:
        pass

    try:
        result = subprocess.run([CONV], capture_output=True, text=True, timeout=120)
    except subprocess.TimeoutExpired:
        pytest.fail("convergence.sh did not reach convergence within 120 seconds.")
    assert result.returncode == 0, f"convergence.sh failed: {result.stderr}"

    n_val, vol_val = parse_result_file()
    assert n_val >= 2000, f"N should be at least 2000, but got {n_val}."
    assert n_val % 1000 == 0 and (n_val // 1000) & ((n_val // 1000) - 1) == 0, (
        f"N must be obtained by repeatedly doubling 1000, but got {n_val}."
    )
    expected_vol = 33.5103
    assert abs(vol_val - expected_vol) <= 1.5, f"Estimated volume {vol_val} is too far from expected ~33.51."


def test_convergence_doubling_and_stopping_logic():
    # Temporarily instrument mc_volume.sh with deterministic outputs so the exact
    # sequence and strict comparison performed by convergence.sh can be checked.
    backup = MC + ".verifier_backup"
    log = "/tmp/convergence_mc_calls"
    if os.path.exists(log):
        os.unlink(log)
    os.replace(MC, backup)
    try:
        with open(MC, "w") as f:
            f.write("""#!/bin/bash
printf '%s\\n' \"$*\" >> /tmp/convergence_mc_calls
[ \"$#\" -eq 4 ] || exit 2
case \"$3\" in
  1000) echo 30.0 ;;
  2000) echo 31.0 ;;
  4000) echo 31.1 ;;
  *) echo 99.0 ;;
esac
""")
        os.chmod(MC, 0o755)
        try:
            os.unlink(RESULT)
        except FileNotFoundError:
            pass

        result = subprocess.run([CONV], capture_output=True, text=True, timeout=15)
        assert result.returncode == 0, f"convergence.sh failed under controlled estimates: {result.stderr}"
        assert os.path.exists(log), "convergence.sh did not call /home/user/mc_volume.sh."
        calls = [line.split() for line in open(log) if line.strip()]
        assert len(calls) == 3, f"Expected calls at N=1000, 2000, and 4000; got {calls}."
        for call, expected_n in zip(calls, [1000, 2000, 4000]):
            assert len(call) == 4, f"mc_volume.sh was called with wrong arguments: {call}"
            assert call[0] == "3" and float(call[1]) == 2.0 and int(call[2]) == expected_n and call[3] == "4", (
                f"Unexpected convergence call: {call}"
            )
        n_val, vol_val = parse_result_file()
        assert n_val == 4000 and abs(vol_val - 31.1) < 1e-9, (
            f"Controlled sequence should stop at N=4000 with volume 31.1, got N={n_val}, Volume={vol_val}."
        )
    finally:
        try:
            os.unlink(MC)
        except FileNotFoundError:
            pass
        os.replace(backup, MC)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
