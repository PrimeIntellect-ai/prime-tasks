#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import stat
import subprocess

CPP_FILE = "/home/user/etl_pipeline.cpp"
RAW_FILE = "/home/user/raw_sensor.csv"
REF_FILE = "/home/user/reference_sensor.csv"
PARAM_FILE = "/home/user/best_param.txt"
BINARY = "/tmp/etl_pipeline_verified"

STANDARD_HEADERS = {
    "algorithm", "any", "array", "atomic", "bitset", "cassert", "cctype",
    "cerrno", "cfenv", "cfloat", "chrono", "cinttypes", "ciso646", "climits",
    "clocale", "cmath", "codecvt", "complex", "condition_variable", "csetjmp",
    "csignal", "cstdarg", "cstdbool", "cstddef", "cstdint", "cstdio", "cstdlib",
    "cstring", "ctgmath", "ctime", "cuchar", "cwchar", "cwctype", "deque",
    "exception", "execution", "filesystem", "forward_list", "fstream",
    "functional", "future", "initializer_list", "iomanip", "ios", "iosfwd",
    "iostream", "istream", "iterator", "list", "locale", "map", "memory",
    "memory_resource", "mutex", "new", "numeric", "optional", "ostream",
    "queue", "random", "ratio", "regex", "scoped_allocator", "set",
    "shared_mutex", "sstream", "stack", "stdexcept", "streambuf", "string",
    "string_view", "strstream", "system_error", "thread", "tuple",
    "type_traits", "typeindex", "typeinfo", "unordered_map", "unordered_set",
    "utility", "valarray", "variant", "vector"
}


def verify_source_and_compile():
    assert os.path.exists(CPP_FILE), f"File {CPP_FILE} does not exist."
    mode = os.lstat(CPP_FILE).st_mode
    assert stat.S_ISREG(mode), f"File {CPP_FILE} must be a regular C++ source file."

    with open(CPP_FILE, "r", encoding="utf-8") as f:
        source = f.read()
    assert source.strip(), f"File {CPP_FILE} is empty."

    includes = re.findall(r"^\s*#\s*include\s*[<\"]([^>\"]+)[>\"]", source, re.MULTILINE)
    nonstandard = [header for header in includes if header not in STANDARD_HEADERS]
    assert not nonstandard, f"Only standard C++ headers are allowed; found: {nonstandard}"

    result = subprocess.run(
        ["g++", "-std=c++17", "-O2", "-Wall", "-Wextra", "-pedantic-errors",
         CPP_FILE, "-o", BINARY],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"etl_pipeline.cpp did not compile as standard C++:\n{result.stderr}"
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), "Compilation did not create an executable."


def compute_expected():
    raw_vals = []
    with open(RAW_FILE, "r") as f:
        for line in f:
            parts = line.strip().split(",")
            if len(parts) == 2:
                if parts[1] == "NaN":
                    raw_vals.append(None)
                else:
                    raw_vals.append(float(parts[1]))

    valid_vals = [v for v in raw_vals if v is not None]
    global_mean = sum(valid_vals) / len(valid_vals)
    imputed_vals = [v if v is not None else global_mean for v in raw_vals]

    mean_imputed = sum(imputed_vals) / len(imputed_vals)
    variance_pop = sum((v - mean_imputed) ** 2 for v in imputed_vals) / len(imputed_vals)
    variance_samp = sum((v - mean_imputed) ** 2 for v in imputed_vals) / (len(imputed_vals) - 1)

    ref_vals = []
    with open(REF_FILE, "r") as f:
        for line in f:
            parts = line.strip().split(",")
            if len(parts) == 2:
                ref_vals.append(float(parts[1]))

    assert len(raw_vals) == len(ref_vals) and raw_vals, "Input datasets must be nonempty and aligned."

    def get_best_for_std(std_dev):
        upper_bound = mean_imputed + 3 * std_dev
        lower_bound = mean_imputed - 3 * std_dev
        capped_vals = [max(lower_bound, min(upper_bound, v)) for v in imputed_vals]

        best_w = None
        best_mse = float("inf")
        for w in [1, 3, 5, 7, 9, 11]:
            smoothed = []
            for i in range(len(capped_vals)):
                start = max(0, i - w + 1)
                window = capped_vals[start:i + 1]
                smoothed.append(sum(window) / len(window))
            mse = sum((s - r) ** 2 for s, r in zip(smoothed, ref_vals)) / len(ref_vals)
            if mse < best_mse:
                best_mse = mse
                best_w = w
        return best_w, best_mse

    return [get_best_for_std(math.sqrt(variance_pop)),
            get_best_for_std(math.sqrt(variance_samp))]


def run_pipeline_and_check():
    expected_results = compute_expected()
    if os.path.lexists(PARAM_FILE):
        os.remove(PARAM_FILE)

    result = subprocess.run(
        [BINARY], cwd="/home/user", stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=20
    )
    assert result.returncode == 0, f"Compiled ETL pipeline failed when run:\n{result.stderr}"
    assert os.path.isfile(PARAM_FILE), f"File {PARAM_FILE} does not exist. The pipeline did not output the result."

    with open(PARAM_FILE, "r") as f:
        content = f.read().strip()

    # Require exactly four digits after the decimal point.
    match = re.fullmatch(r"W=(\d+), MSE=(\d+\.\d{4})", content)
    assert match, (f"Content of {PARAM_FILE} does not match the required format "
                   f"'W=[best_W], MSE=[lowest_MSE_rounded_to_4_decimal_places]'. Found: '{content}'")

    w_val = int(match.group(1))
    mse_val = float(match.group(2))

    # Preserve the original numerical assertion, accepting population or sample std_dev.
    valid = False
    for expected_w, expected_mse in expected_results:
        if w_val == expected_w and abs(mse_val - expected_mse) < 0.01:
            valid = True
            break
    assert valid, (f"The values W={w_val}, MSE={mse_val} are incorrect. Expected "
                   f"W={expected_results[0][0]}, MSE around {expected_results[0][1]:.4f}.")

    rounded_valid = any(
        w_val == expected_w and match.group(2) == f"{expected_mse:.4f}"
        for expected_w, expected_mse in expected_results
    )
    assert rounded_valid, "MSE is not the correctly rounded value to exactly four decimal places."


def write_generated_case(seed, phase, noise):
    rng = random.Random(seed)
    n = 1000
    reference = []
    raw = []
    for i in range(n):
        signal = 18.0 + 7.5 * math.sin(i * phase) + 2.0 * math.cos(i * phase * 0.31)
        reference.append(signal + rng.gauss(0.0, 0.07))
        raw.append(signal + rng.gauss(0.0, noise))

    indices = list(range(n))
    rng.shuffle(indices)
    missing = set(indices[:47])
    high = indices[47:66]
    low = indices[66:85]
    for i in high:
        raw[i] += 45.0 + rng.random() * 15.0
    for i in low:
        raw[i] -= 45.0 + rng.random() * 15.0

    with open(REF_FILE, "w") as f:
        for i, value in enumerate(reference):
            f.write(f"{i},{value:.4f}\n")
    with open(RAW_FILE, "w") as f:
        for i, value in enumerate(raw):
            if i in missing:
                f.write(f"{i},NaN\n")
            else:
                f.write(f"{i},{value:.4f}\n")


def main():
    verify_source_and_compile()
    with open(RAW_FILE, "rb") as f:
        original_raw = f.read()
    with open(REF_FILE, "rb") as f:
        original_ref = f.read()

    try:
        # Check the required supplied datasets first.
        run_pipeline_and_check()

        # Exercise the compiled artifact on unseen inputs whose answers are derived here.
        seed = int.from_bytes(os.urandom(8), "big")
        write_generated_case(seed, 0.037, 1.7)
        run_pipeline_and_check()
        write_generated_case(seed ^ 0x9E3779B97F4A7C15, 0.061, 2.3)
        run_pipeline_and_check()
    finally:
        with open(RAW_FILE, "wb") as f:
            f.write(original_raw)
        with open(REF_FILE, "wb") as f:
            f.write(original_ref)

    # Leave the requested result for the original datasets in place.
    run_pipeline_and_check()


if __name__ == "__main__":
    main()
TEST_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
