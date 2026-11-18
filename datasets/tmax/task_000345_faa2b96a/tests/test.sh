#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import re
import shutil
import subprocess
import textwrap
from pathlib import Path


def parse_results(results_path):
    with open(results_path, "r") as f:
        content = f.read().strip().splitlines()

    assert len(content) == 2, f"{results_path} should contain exactly 2 lines."

    row_match = re.match(r"^Row-major mean:\s+(\d+)\s+us$", content[0])
    col_match = re.match(r"^Col-major mean:\s+(\d+)\s+us$", content[1])

    assert row_match is not None, f"First line of {results_path} does not match expected format."
    assert col_match is not None, f"Second line of {results_path} does not match expected format."

    return int(row_match.group(1)), int(col_match.group(1))


def test_benchmark_cpp_exists():
    """Test that the benchmark.cpp file exists."""
    assert os.path.isfile("/home/user/benchmark.cpp"), "/home/user/benchmark.cpp does not exist."


def test_pipeline_sh_exists_and_executable():
    """Test that the pipeline.sh script exists and is executable."""
    script_path = "/home/user/pipeline.sh"
    assert os.path.isfile(script_path), f"{script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."


def test_results_txt_exists_and_format():
    """Test that results.txt exists, has the correct format, and col-major is slower than row-major."""
    results_path = "/home/user/results.txt"
    assert os.path.isfile(results_path), f"{results_path} does not exist."
    row_mean, col_mean = parse_results(results_path)
    assert col_mean > row_mean, f"Col-major mean ({col_mean}) is not greater than Row-major mean ({row_mean})."


def test_benchmark_and_pipeline_are_executed_and_results_are_recomputed():
    # Compile the submitted source independently with the required options.
    checked_binary = "/tmp/benchmark_checked"
    compile_result = subprocess.run(
        ["/usr/bin/g++", "-O0", "-std=c++11", "/home/user/benchmark.cpp", "-o", checked_binary],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert compile_result.returncode == 0, f"benchmark.cpp failed to compile: {compile_result.stderr}"

    # Independently derive the sum produced by mt19937(seed 42) and uniform integers 1..100.
    oracle_source = "/tmp/expected_sum.cpp"
    oracle_binary = "/tmp/expected_sum"
    Path(oracle_source).write_text(textwrap.dedent(r'''
        #include <iostream>
        #include <random>
        #include <cstdlib>
        int main(int argc, char **argv) {
            if (argc != 2) return 2;
            int n = std::atoi(argv[1]);
            std::mt19937 rng(42);
            std::uniform_int_distribution<int> dist(1, 100);
            long long sum = 0;
            for (long long i = 0; i < 1LL * n * n; ++i) sum += dist(rng);
            std::cout << sum;
            return 0;
        }
    '''))
    subprocess.run(
        ["/usr/bin/g++", "-O0", "-std=c++11", oracle_source, "-o", oracle_binary],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    expected_sum = int(subprocess.check_output([oracle_binary, "73"], text=True, timeout=10).strip())

    observed_sums = []
    for mode in (0, 1):
        previous = None
        for _ in range(2):
            run = subprocess.run(
                [checked_binary, "73", str(mode)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=10,
            )
            assert run.returncode == 0, f"benchmark failed in mode {mode}: {run.stderr}"
            assert re.fullmatch(r"\s*\d+\s*", run.stdout), \
                f"benchmark stdout must contain only elapsed integer microseconds, got {run.stdout!r}"
            numbers = [int(x) for x in re.findall(r"-?\d+", run.stderr)]
            assert expected_sum in numbers, \
                f"benchmark stderr did not contain the expected reproducible sum {expected_sum}: {run.stderr!r}"
            if previous is not None:
                assert run.stderr == previous, "The printed sum is not reproducible across identical runs."
            previous = run.stderr
        observed_sums.append(previous)
    assert observed_sums[0] == observed_sums[1], "Row-major and column-major traversals produced different sums."

    # Put a controlled g++ at the front of PATH. It enforces the required compile
    # command and replaces the freshly compiled benchmark with a transparent
    # recorder, allowing the report to be checked against the actual 20 outputs.
    bindir = Path("/tmp/verifier-bin")
    runs_dir = Path("/tmp/verifier-runs")
    compile_log = Path("/tmp/verifier-compile.log")
    shutil.rmtree(bindir, ignore_errors=True)
    shutil.rmtree(runs_dir, ignore_errors=True)
    bindir.mkdir()
    runs_dir.mkdir()
    compile_log.unlink(missing_ok=True)

    recorder = Path("/tmp/verifier-benchmark-recorder")
    recorder.write_text(r'''#!/bin/bash
run_dir=$(mktemp -d /tmp/verifier-runs/run.XXXXXX) || exit 98
printf '%s' "$1" > "$run_dir/n"
printf '%s' "$2" > "$run_dir/mode"
set +e
/home/user/benchmark.verifier_real "$@" > "$run_dir/stdout" 2> "$run_dir/stderr"
rc=$?
set -e
printf '%s' "$rc" > "$run_dir/status"
cat "$run_dir/stdout"
cat "$run_dir/stderr" >&2
exit "$rc"
''')
    recorder.chmod(0o755)

    compiler_wrapper = bindir / "g++"
    compiler_wrapper.write_text(r'''#!/bin/bash
set -e
if [ "$#" -ne 5 ] || [ "$1" != "-O0" ] || [ "$2" != "-std=c++11" ] || \
   [ "$3" != "/home/user/benchmark.cpp" ] || [ "$4" != "-o" ] || \
   [ "$5" != "/home/user/benchmark" ]; then
    echo "pipeline did not use the required g++ command" >&2
    exit 97
fi
/usr/bin/g++ "$@"
rm -f /home/user/benchmark.verifier_real
mv /home/user/benchmark /home/user/benchmark.verifier_real
cp /tmp/verifier-benchmark-recorder /home/user/benchmark
chmod +x /home/user/benchmark
printf 'compiled\n' >> /tmp/verifier-compile.log
''')
    compiler_wrapper.chmod(0o755)

    Path("/home/user/results.txt").unlink(missing_ok=True)
    env = os.environ.copy()
    env["PATH"] = str(bindir) + os.pathsep + env.get("PATH", "")

    try:
        pipeline = subprocess.run(
            ["/bin/bash", "/home/user/pipeline.sh"],
            cwd="/home/user",
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=420,
        )
        assert pipeline.returncode == 0, \
            f"pipeline.sh failed when executed. stdout={pipeline.stdout!r} stderr={pipeline.stderr!r}"

        assert compile_log.is_file(), "pipeline.sh did not invoke g++ through the required command."
        assert compile_log.read_text().splitlines() == ["compiled"], \
            "pipeline.sh must compile benchmark.cpp exactly once."

        records = []
        for directory_name in glob.glob("/tmp/verifier-runs/run.*"):
            directory = Path(directory_name)
            assert (directory / "status").read_text() == "0", "A benchmark invocation failed."
            n = (directory / "n").read_text()
            mode = (directory / "mode").read_text()
            raw_output = (directory / "stdout").read_text()
            assert n == "4000", f"pipeline used N={n!r}, expected N=4000."
            assert mode in ("0", "1"), f"pipeline used invalid mode {mode!r}."
            assert re.fullmatch(r"\s*\d+\s*", raw_output), \
                f"benchmark output was not an integer number of microseconds: {raw_output!r}"
            records.append((mode, int(raw_output.strip())))

        row_times = [value for mode, value in records if mode == "0"]
        col_times = [value for mode, value in records if mode == "1"]
        assert len(records) == 20, f"pipeline ran the benchmark {len(records)} times instead of 20."
        assert len(row_times) == 10, f"pipeline made {len(row_times)} row-major runs instead of 10."
        assert len(col_times) == 10, f"pipeline made {len(col_times)} column-major runs instead of 10."

        results_path = "/home/user/results.txt"
        assert os.path.isfile(results_path), f"{results_path} was not generated by pipeline.sh."
        row_mean, col_mean = parse_results(results_path)

        # Integer output is commonly produced either by truncating integer division
        # or by formatting the arithmetic mean to the nearest integer.
        def valid_integer_means(values):
            total = sum(values)
            return {total // len(values), (2 * total + len(values)) // (2 * len(values))}

        assert row_mean in valid_integer_means(row_times), \
            f"Reported row mean {row_mean} was not computed from observed runs {row_times}."
        assert col_mean in valid_integer_means(col_times), \
            f"Reported column mean {col_mean} was not computed from observed runs {col_times}."
        assert col_mean > row_mean, \
            f"Col-major mean ({col_mean}) is not greater than Row-major mean ({row_mean})."
    finally:
        real_binary = Path("/home/user/benchmark.verifier_real")
        if real_binary.exists():
            Path("/home/user/benchmark").unlink(missing_ok=True)
            os.replace(real_binary, "/home/user/benchmark")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
