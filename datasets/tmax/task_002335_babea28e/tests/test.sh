#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import shutil
import subprocess
import textwrap
import pytest

WORKSPACE_DIR = "/home/user/workspace"
AUTH_MODULE_DIR = os.path.join(WORKSPACE_DIR, "auth_module")
CI_RUN_SH = os.path.join(AUTH_MODULE_DIR, "ci_run.sh")
CI_RESULT_LOG = os.path.join(WORKSPACE_DIR, "ci_result.log")
CMAKE_LISTS = os.path.join(AUTH_MODULE_DIR, "CMakeLists.txt")
AUTH_TEST_CPP = os.path.join(AUTH_MODULE_DIR, "auth_test.cpp")
BUILD_DIR = os.path.join(AUTH_MODULE_DIR, "build")
AUTH_TEST_BIN = os.path.join(BUILD_DIR, "auth_test")
MOCK_LIB = "/home/user/opt/mock_libs/libmock_waf.so"


def test_ci_run_script_exists_and_executable():
    assert os.path.isfile(CI_RUN_SH), f"CI script not found at {CI_RUN_SH}"
    st = os.stat(CI_RUN_SH)
    assert bool(st.st_mode & stat.S_IXUSR), f"CI script at {CI_RUN_SH} is not executable"


def test_execute_ci_pipeline_from_clean_state():
    shutil.rmtree(BUILD_DIR, ignore_errors=True)
    if os.path.exists(CI_RESULT_LOG):
        os.remove(CI_RESULT_LOG)

    env = os.environ.copy()
    env.pop("LD_LIBRARY_PATH", None)
    result = subprocess.run(
        [CI_RUN_SH], cwd=AUTH_MODULE_DIR, env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=120
    )
    assert result.returncode == 0, (
        f"ci_run.sh failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    assert os.path.isdir(BUILD_DIR), "ci_run.sh did not create the build directory"
    assert os.path.isfile(os.path.join(BUILD_DIR, "CMakeCache.txt")), "CMake was not run"
    assert os.path.isfile(os.path.join(BUILD_DIR, "Makefile")), "CMake did not generate Makefiles"
    assert os.path.isfile(AUTH_TEST_BIN), "ci_run.sh did not build auth_test"
    assert os.access(AUTH_TEST_BIN, os.X_OK), "Built auth_test is not executable"
    with open(AUTH_TEST_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Built auth_test is not an ELF executable"

    with open(os.path.join(BUILD_DIR, "CMakeCache.txt"), "r", errors="replace") as f:
        cache = f.read()
    flags = re.search(r"^CMAKE_CXX_FLAGS:STRING=(.*)$", cache, re.MULTILINE)
    assert flags is not None, "CMAKE_CXX_FLAGS is missing from CMakeCache.txt"
    assert "-fsanitize=address" in flags.group(1), "AddressSanitizer was not enabled"
    assert "-g" in flags.group(1), "Debug information was not enabled"


def test_ci_result_log_exists():
    assert os.path.isfile(CI_RESULT_LOG), f"Result log not found at {CI_RESULT_LOG}"


def test_ci_result_log_content():
    with open(CI_RESULT_LOG, 'r') as f:
        content = f.read()

    assert "All tests passed!" in content, "Log does not contain 'All tests passed!'"

    asan_keywords = ["AddressSanitizer", "leak", "ERROR: LeakSanitizer"]
    for kw in asan_keywords:
        assert kw not in content, f"Log contains ASan error/warning keyword: {kw}"


def test_cmake_lists_fixed():
    assert os.path.isfile(CMAKE_LISTS), f"CMakeLists.txt not found at {CMAKE_LISTS}"
    with open(CMAKE_LISTS, 'r') as f:
        content = f.read()

    assert "target_link_libraries" in content, "CMakeLists.txt is missing target_link_libraries"
    assert "RPATH" in content or "rpath" in content.lower(), "CMakeLists.txt is missing RPATH configuration"
    assert "mock_waf" in content or "libmock_waf.so" in content, "CMakeLists.txt does not link against mock_waf"


def test_built_binary_has_real_linkage_rpath_and_asan():
    env = os.environ.copy()
    env.pop("LD_LIBRARY_PATH", None)

    ldd = subprocess.run(["ldd", AUTH_TEST_BIN], env=env, text=True,
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
    assert ldd.returncode == 0, f"ldd failed: {ldd.stderr}"
    assert re.search(r"libmock_waf\.so\s*=>\s*/home/user/opt/mock_libs/libmock_waf\.so", ldd.stdout), (
        "auth_test does not resolve libmock_waf.so from /home/user/opt/mock_libs without LD_LIBRARY_PATH"
    )
    assert "libasan" in ldd.stdout, "Built auth_test is not linked to AddressSanitizer"

    dynamic = subprocess.run(["readelf", "-d", AUTH_TEST_BIN], text=True,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
    assert dynamic.returncode == 0, f"readelf failed: {dynamic.stderr}"
    assert re.search(r"\((?:RPATH|RUNPATH)\).*?/home/user/opt/mock_libs", dynamic.stdout), (
        "auth_test has no RPATH/RUNPATH for /home/user/opt/mock_libs"
    )


def test_built_auth_test_really_runs_cleanly():
    env = os.environ.copy()
    env.pop("LD_LIBRARY_PATH", None)
    env["ASAN_OPTIONS"] = "detect_leaks=1:halt_on_error=1:exitcode=99"
    result = subprocess.run([AUTH_TEST_BIN], cwd=BUILD_DIR, env=env, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
    combined = result.stdout + result.stderr
    assert result.returncode == 0, f"auth_test failed with code {result.returncode}:\n{combined}"
    assert "All tests passed!" in result.stdout, "auth_test did not report success"
    assert "AddressSanitizer" not in combined, f"AddressSanitizer reported an error:\n{combined}"
    assert "LeakSanitizer" not in combined, f"LeakSanitizer reported an error:\n{combined}"


def test_auth_test_cpp_fixed():
    assert os.path.isfile(AUTH_TEST_CPP), f"auth_test.cpp not found at {AUTH_TEST_CPP}"
    with open(AUTH_TEST_CPP, 'r') as f:
        content = f.read()

    malformed_block = re.search(r'if\s*\(\s*token\s*==\s*"malformed"\s*\)\s*\{([^}]+)\}', content)
    assert malformed_block is not None, "Could not find 'malformed' if-block in auth_test.cpp"
    assert "delete[]" in malformed_block.group(1), "Memory leak not fixed: missing 'delete[] buffer;' in 'malformed' token branch"

    assert 'return "";' not in content, "generate_attack_payload is still returning an empty string"


def test_generated_payload_constraints_independently():
    obj = "/tmp/auth_submission.o"
    harness_cpp = "/tmp/payload_harness.cpp"
    harness_bin = "/tmp/payload_harness"

    with open(harness_cpp, "w") as f:
        f.write(textwrap.dedent(r'''
            #include <string>
            std::string generate_attack_payload();
            int main() {
                const std::string payload = generate_attack_payload();
                if (payload.size() != 16) return 10;
                if (payload.compare(0, 5, "admin") != 0) return 11;
                int sum = 0;
                for (std::size_t i = 0; i < payload.size(); ++i) {
                    unsigned char c = static_cast<unsigned char>(payload[i]);
                    if (c < 32 || c > 126) return 12;
                    if (i >= 5) sum += c;
                }
                if (sum != 1000) return 13;
                return 0;
            }
        '''))

    compile_obj = subprocess.run(
        ["g++", "-std=c++17", "-Dmain=auth_module_original_main", "-c", AUTH_TEST_CPP, "-o", obj],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert compile_obj.returncode == 0, f"Could not compile auth_test.cpp for payload test:\n{compile_obj.stderr}"

    link = subprocess.run(
        ["g++", "-std=c++17", harness_cpp, obj, MOCK_LIB,
         "-Wl,-rpath,/home/user/opt/mock_libs", "-o", harness_bin],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert link.returncode == 0, f"Could not link payload test harness:\n{link.stderr}"

    result = subprocess.run([harness_bin], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
    meanings = {
        10: "payload is not exactly 16 characters",
        11: "payload does not start with admin",
        12: "payload contains non-printable ASCII",
        13: "ASCII sum of the final 11 characters is not 1000",
    }
    assert result.returncode == 0, meanings.get(result.returncode, f"payload harness failed with code {result.returncode}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
