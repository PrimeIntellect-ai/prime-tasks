#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import shlex
import subprocess
import tempfile
import uuid

import pytest

HOME_DIR = "/home/user"
DATA_PIPELINE_DIR = os.path.join(HOME_DIR, "data_pipeline")
C_LIB_DIR = os.path.join(DATA_PIPELINE_DIR, "c_lib")
RUST_APP_DIR = os.path.join(DATA_PIPELINE_DIR, "rust_app")
RUST_SRC_DIR = os.path.join(RUST_APP_DIR, "src")
BINARY_PATH = os.path.join(RUST_APP_DIR, "target", "release", "rust_app")


def run_checked(cmd, **kwargs):
    result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, timeout=120, **kwargs)
    assert result.returncode == 0, (
        f"Command failed: {cmd}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


@pytest.fixture(scope="session", autouse=True)
def build_real_artifacts():
    for name in ("filter.o", "libfilter.a"):
        path = os.path.join(C_LIB_DIR, name)
        if os.path.lexists(path):
            os.unlink(path)

    run_checked(["make", "-B"], cwd=C_LIB_DIR)

    lib_path = os.path.join(C_LIB_DIR, "libfilter.a")
    assert os.path.isfile(lib_path), f"Static library {lib_path} was not created by make."
    archive = run_checked(["ar", "t", lib_path])
    assert archive.stdout.strip(), "libfilter.a is empty or is not a usable archive."
    symbols = run_checked(["nm", "-g", lib_path])
    assert "filter_add" in symbols.stdout and "filter_check" in symbols.stdout, \
        "libfilter.a does not contain the required C functions."

    run_checked(["cargo", "clean"], cwd=RUST_APP_DIR)
    env = os.environ.copy()
    env["RUSTFLAGS"] = "-D warnings"
    run_checked(["cargo", "build", "--release"], cwd=RUST_APP_DIR, env=env)

    assert os.path.isfile(BINARY_PATH), "cargo build --release did not create the Rust binary."
    assert os.access(BINARY_PATH, os.X_OK), "The release Rust binary is not executable."
    binary_symbols = run_checked(["nm", BINARY_PATH])
    assert "filter_add" in binary_symbols.stdout and "filter_check" in binary_symbols.stdout, \
        "The release binary is not linked with the required C filter functions."


def test_makefile_and_libfilter():
    lib_path = os.path.join(C_LIB_DIR, "libfilter.a")
    assert os.path.isfile(lib_path), f"Static library {lib_path} was not created."

    makefile_path = os.path.join(C_LIB_DIR, "Makefile")
    with open(makefile_path, "r") as f:
        content = f.read()
        assert "ar " in content, "Makefile does not appear to use 'ar' to create the static library."


def test_build_rs_fixed():
    build_rs = os.path.join(RUST_APP_DIR, "build.rs")
    with open(build_rs, "r") as f:
        content = f.read()

    lines = [line.strip() for line in content.splitlines()
             if line.strip() and not line.strip().startswith("//")]
    joined_lines = "".join(lines)

    assert "cargo:rustc-link-search" in joined_lines, "build.rs is missing 'cargo:rustc-link-search' instruction."
    assert "cargo:rustc-link-lib" in joined_lines, "build.rs is missing 'cargo:rustc-link-lib' instruction."


def test_main_rs_lifetime_fixed():
    main_rs = os.path.join(RUST_SRC_DIR, "main.rs")
    with open(main_rs, "r") as f:
        content = f.read()

    bug_pattern = r"CString::new\([^)]+\)\.unwrap\(\)\.as_ptr\(\)"
    assert not re.search(bug_pattern, content), "main.rs still contains the inline CString::new(...).unwrap().as_ptr() lifetime bug."


def test_run_pipeline_script():
    script_path = os.path.join(HOME_DIR, "run_pipeline.sh")
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {script_path} is not executable."

    with open(script_path, "r") as f:
        script = f.read()
    assert "/home/user/data.txt" in script, "The pipeline script does not use /home/user/data.txt."
    assert BINARY_PATH in script, "The pipeline script does not invoke the required release binary path."
    assert "/home/user/results.txt" in script, "The pipeline script does not write /home/user/results.txt."
    assert "/home/user/bench_log.txt" in script, "The pipeline script does not write /home/user/bench_log.txt."
    assert re.search(r"\btime\s+-p\b", script), "The pipeline script does not use time -p."

    data_path = os.path.join(HOME_DIR, "data.txt")
    results_path = os.path.join(HOME_DIR, "results.txt")
    bench_path = os.path.join(HOME_DIR, "bench_log.txt")
    with open(data_path, "rb") as f:
        original_data = f.read()

    dynamic_data = b"banana\nkiwi\napple\napple\nBANANA\nbanana\n"
    expected_lines = ["MATCH: banana", "MATCH: apple", "MATCH: apple", "MATCH: banana"]
    real_binary = BINARY_PATH + ".verifier-real"
    marker = os.path.join(tempfile.gettempdir(), "pipeline-invocation-" + uuid.uuid4().hex)

    os.replace(BINARY_PATH, real_binary)
    wrapper = (
        "#!/bin/sh\n"
        f"printf '%s\\n' \"$#\" \"$1\" > {shlex.quote(marker)}\n"
        f"exec {shlex.quote(real_binary)} \"$@\"\n"
    )
    with open(BINARY_PATH, "w") as f:
        f.write(wrapper)
    os.chmod(BINARY_PATH, 0o755)

    try:
        with open(data_path, "wb") as f:
            f.write(dynamic_data)

        direct = run_checked([real_binary, data_path])
        direct_lines = [line.strip() for line in direct.stdout.splitlines() if line.strip()]
        assert direct_lines == expected_lines, \
            f"The compiled Rust binary produced {direct_lines}, expected {expected_lines}."

        for path in (results_path, bench_path, marker):
            if os.path.lexists(path):
                os.unlink(path)

        run_checked([script_path], cwd=HOME_DIR)
        assert os.path.isfile(marker), "run_pipeline.sh did not invoke the required release binary."
        with open(marker, "r") as f:
            invocation = f.read().splitlines()
        assert invocation == ["1", data_path], \
            f"The release binary was not invoked with exactly {data_path} as its first argument: {invocation}"

        assert os.path.isfile(results_path), "The script did not create results.txt."
        with open(results_path, "r") as f:
            pipeline_output = f.read()
        assert pipeline_output == direct.stdout, \
            "results.txt is not exactly the standard output of the compiled Rust binary."

        assert os.path.isfile(bench_path), "The script did not create bench_log.txt."
        with open(bench_path, "r") as f:
            bench = f.read().strip()
        assert re.fullmatch(r"(?:\d+(?:\.\d*)?|\.\d+)", bench), \
            f"bench_log.txt must contain only one non-negative decimal value, found: {bench!r}"
        assert float(bench) >= 0.0
    finally:
        with open(data_path, "wb") as f:
            f.write(original_data)
        try:
            for path in (results_path, bench_path):
                if os.path.lexists(path):
                    os.unlink(path)
            subprocess.run([script_path], cwd=HOME_DIR, stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE, text=True, timeout=120)
        finally:
            if os.path.lexists(BINARY_PATH):
                os.unlink(BINARY_PATH)
            os.replace(real_binary, BINARY_PATH)
            if os.path.lexists(marker):
                os.unlink(marker)


def test_results_txt():
    results_path = os.path.join(HOME_DIR, "results.txt")
    assert os.path.isfile(results_path), f"Results file {results_path} does not exist. Did the script run successfully?"

    with open(results_path, "r") as f:
        content = f.read().strip()

    expected_lines = ["MATCH: apple", "MATCH: banana"]
    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]

    assert actual_lines == expected_lines, f"Expected {expected_lines} in results.txt, but got {actual_lines}"


def test_bench_log_txt():
    bench_log_path = os.path.join(HOME_DIR, "bench_log.txt")
    assert os.path.isfile(bench_log_path), f"Benchmark log {bench_log_path} does not exist."

    with open(bench_log_path, "r") as f:
        content = f.read().strip()

    try:
        val = float(content)
        assert val >= 0.0, "Execution time cannot be negative."
    except ValueError:
        pytest.fail(f"bench_log.txt does not contain a valid float. Found: {content}")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
