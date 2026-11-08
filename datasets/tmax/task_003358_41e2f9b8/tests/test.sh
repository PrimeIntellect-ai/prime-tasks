#!/bin/bash
set -u
mkdir -p /logs/verifier

verify() {
    cd /home/user/project || return 1

    # Build the submitted project from a clean build directory and run the
    # submitted test executable. Remove any pre-created result first.
    rm -rf /home/user/project/build
    mkdir -p /home/user/project/build
    rm -f /home/user/project/test_result.log
    cmake -S /home/user/project -B /home/user/project/build || return 1
    cmake --build /home/user/project/build --clean-first || return 1
    test -x /home/user/project/build/test_app || return 1
    timeout 20s /home/user/project/build/test_app || return 1

    cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re


def test_cmakelists_linked():
    cmakelists_path = "/home/user/project/CMakeLists.txt"
    assert os.path.isfile(cmakelists_path), f"File {cmakelists_path} is missing."

    with open(cmakelists_path, "r") as f:
        content = f.read()

    match = re.search(r"target_link_libraries\s*\(\s*test_app\s+(?:PRIVATE\s+|PUBLIC\s+|INTERFACE\s+)?math_lib\s*\)", content)
    assert match is not None, "CMakeLists.txt does not correctly link test_app against math_lib using target_link_libraries."


def test_math_lib_cpp_fixed():
    math_lib_cpp_path = "/home/user/project/src/math_lib.cpp"
    assert os.path.isfile(math_lib_cpp_path), f"File {math_lib_cpp_path} is missing."

    with open(math_lib_cpp_path, "r") as f:
        content = f.read()

    assert "i <= v.size()" not in content, "The out-of-bounds bug 'i <= v.size()' is still present in math_lib.cpp."
    assert re.search(r"i\s*<\s*v\.size\(\)", content) or re.search(r"i\s*!=\s*v\.size\(\)", content), \
        "math_lib.cpp does not seem to contain a corrected loop boundary (e.g., i < v.size())."


def test_test_result_log():
    log_path = "/home/user/project/test_result.log"
    assert os.path.isfile(log_path), f"The test result log file {log_path} was not created. Did you compile and run the test_app?"

    with open(log_path, "r") as f:
        content = f.read().strip()

    assert content == "PROPERTY_TEST_PASSED", f"Expected the log file to contain exactly 'PROPERTY_TEST_PASSED', but found '{content}'."


def test_test_app_cpp_modified():
    test_app_cpp_path = "/home/user/project/test/test_app.cpp"
    assert os.path.isfile(test_app_cpp_path), f"File {test_app_cpp_path} is missing."

    with open(test_app_cpp_path, "r") as f:
        content = f.read()

    assert "100" in content, "test_app.cpp does not seem to contain the logic for 100 random vectors."
    assert "PROPERTY_TEST_PASSED" in content, "test_app.cpp does not contain the success string to write to the log."
    assert "PROPERTY_TEST_FAILED" in content, "test_app.cpp does not contain the failure string to write to the log."
    assert "test_result.log" in content, "test_app.cpp does not contain the filename 'test_result.log' to write to."
TEST_EOF

    python3 -m pytest /tmp/test_final_state.py -x --tb=short || return 1

    # Independently exercise solve_constraint on derived inputs under memory and
    # undefined-behavior sanitizers instead of trusting the submitted log.
    cat << 'CPP_EOF' > /tmp/behavior_test.cpp
#include <array>
#include <cstdlib>
#include <iostream>
#include "math_lib.h"

static bool check(std::array<int, 5> input, int target) {
    FixedVector v = {{input[0], input[1], input[2], input[3], input[4]}};
    solve_constraint(v, target);
    if (v.sum() != target) return false;
    for (int i = 0; i < v.size(); ++i) {
        if (v.data[i] < 0) return false;
    }
    return true;
}

int main() {
    const std::array<std::array<int, 5>, 8> inputs = {{
        {{1, 2, 3, 4, 5}},
        {{19, 19, 19, 19, 19}},
        {{0, 0, 0, 0, 0}},
        {{7, 0, 13, 2, 18}},
        {{50, 1, 0, 4, 3}},
        {{100, 100, 100, 100, 100}},
        {{3, 17, 8, 11, 6}},
        {{20, 20, 20, 20, 20}}
    }};
    const std::array<int, 8> targets = {{100, 100, 100, 100, 37, 250, 0, 100}};
    for (std::size_t i = 0; i < inputs.size(); ++i) {
        if (!check(inputs[i], targets[i])) {
            std::cerr << "behavior case " << i << " failed\n";
            return 1;
        }
    }
    return 0;
}
CPP_EOF

    g++ -std=c++17 -O1 -g -fsanitize=address,undefined -fno-omit-frame-pointer \
        -I/home/user/project/include /tmp/behavior_test.cpp \
        /home/user/project/src/math_lib.cpp -o /tmp/behavior_test || return 1
    ASAN_OPTIONS=detect_leaks=0 timeout 20s /tmp/behavior_test || return 1

    # Recompile the submitted property test against an instrumented implementation.
    # The success run verifies it invokes solve_constraint at least 100 times on
    # suitable generated values. The injected-failure run verifies it detects a
    # bad result rather than unconditionally writing the success marker.
    cat << 'CPP_EOF' > /tmp/spy_math.cpp
#include "math_lib.h"
#include <cstdlib>
#include <fstream>

static int calls = 0;
static bool valid_inputs = true;

struct Reporter {
    ~Reporter() {
        std::ofstream out("/tmp/spy_report.txt");
        out << calls << " " << (valid_inputs ? 1 : 0) << "\n";
    }
} reporter;

int FixedVector::sum() const {
    int total = 0;
    for (int i = 0; i < size(); ++i) total += data[i];
    return total;
}

void solve_constraint(FixedVector& v, int target_sum) {
    ++calls;
    if (target_sum != 100) valid_inputs = false;
    for (int i = 0; i < v.size(); ++i) {
        if (v.data[i] < 0 || v.data[i] > 20) valid_inputs = false;
    }

    const char* fail = std::getenv("SPY_INJECT_FAILURE");
    if (fail && fail[0] == '1' && calls == 2) {
        v.data[0] = -1;
        for (int i = 1; i < v.size(); ++i) v.data[i] = 0;
        return;
    }

    v.data[0] = target_sum;
    for (int i = 1; i < v.size(); ++i) v.data[i] = 0;
}
CPP_EOF

    g++ -std=c++17 -O2 -I/home/user/project/include \
        /home/user/project/test/test_app.cpp /tmp/spy_math.cpp \
        -o /tmp/instrumented_test_app || return 1

    rm -f /home/user/project/test_result.log /tmp/spy_report.txt
    timeout 20s /tmp/instrumented_test_app || return 1
    test -f /tmp/spy_report.txt || return 1
    read -r call_count valid_inputs < /tmp/spy_report.txt
    test "$call_count" -ge 100 || return 1
    test "$valid_inputs" = "1" || return 1
    test "$(cat /home/user/project/test_result.log 2>/dev/null)" = "PROPERTY_TEST_PASSED" || return 1

    rm -f /home/user/project/test_result.log /tmp/spy_report.txt
    SPY_INJECT_FAILURE=1 timeout 20s /tmp/instrumented_test_app
    status=$?
    test "$status" -ne 124 || return 1
    test -f /home/user/project/test_result.log || return 1
    test "$(cat /home/user/project/test_result.log)" = "PROPERTY_TEST_FAILED" || return 1

    return 0
}

if verify; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
