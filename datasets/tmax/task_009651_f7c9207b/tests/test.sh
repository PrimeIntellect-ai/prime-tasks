#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'EXPECTED_EOF' > /tmp/expected_sanitizer_test.go
package main

/*
#cgo CXXFLAGS: -std=c++11
#include <stdlib.h>

char* strip_tags(const char* input);
void free_string(char* str);
*/
import "C"
import (
	"sync"
	"testing"
	"unsafe"
)

func sanitize(input string) string {
	cStr := C.CString(input)
	defer C.free(unsafe.Pointer(cStr))

	cOut := C.strip_tags(cStr)
	defer C.free_string(cOut)

	return C.GoString(cOut)
}

func TestConcurrentSanitization(t *testing.T) {
	var wg sync.WaitGroup
	inputs := []string{
		"Hello World",
		"<b>Hello</b> <i>World</i>",
		"<script>alert(1)</script>",
		"No tags here at all!",
		"An unfinished <tag",
	}

	// Concurrent property-based fuzzing simulation
	for i := 0; i < 1000; i++ {
		wg.Add(1)
		go func(iter int) {
			defer wg.Done()
			in := inputs[iter%len(inputs)]
			_ = sanitize(in)
		}(i)
	}
	wg.Wait()
}

func BenchmarkSanitize(b *testing.B) {
	for i := 0; i < b.N; i++ {
		sanitize("<b>Testing</b> benchmark <script>alert('test')</script>")
	}
}
EXPECTED_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import textwrap
import pytest

CWD = "/home/user/api-gateway"
BENCH = os.path.join(CWD, "bench_results.txt")


def run(command, **kwargs):
    try:
        return subprocess.run(command, capture_output=True, text=True, **kwargs)
    except FileNotFoundError:
        pytest.fail(f"Required command was not found: {command[0]}")
    except subprocess.TimeoutExpired:
        pytest.fail(f"Command timed out: {' '.join(command)}")


def assert_benchmark_output(content):
    assert re.search(r"(?m)^goos:\s+\S+\s*$", content), "Missing goos header"
    assert re.search(r"(?m)^goarch:\s+\S+\s*$", content), "Missing goarch header"
    assert re.search(r"(?m)^pkg:\s+api-gateway\s*$", content), "Missing package header"
    match = re.search(
        r"(?m)^BenchmarkSanitize(?:-\d+)?\s+(\d+)\s+([0-9]+(?:\.[0-9]+)?)\s+ns/op(?:\s|$)",
        content,
    )
    assert match, "No valid BenchmarkSanitize result line was found"
    assert int(match.group(1)) > 0
    assert float(match.group(2)) > 0
    assert re.search(r"(?m)^PASS\s*$", content), "Benchmark output does not report PASS"
    assert re.search(r"(?m)^ok\s+api-gateway\s+", content), "Benchmark output lacks the final Go result"


def test_bench_results_exists():
    assert os.path.isfile(BENCH), f"File {BENCH} does not exist. Did you run the benchmark and save the output?"


def test_bench_results_content():
    assert os.path.isfile(BENCH), f"File {BENCH} does not exist."
    with open(BENCH, "r", encoding="utf-8", errors="replace") as f:
        content = f.read()
    assert "BenchmarkSanitize" in content, f"File {BENCH} does not contain 'BenchmarkSanitize'. Ensure you ran the benchmark correctly."
    assert_benchmark_output(content)


def test_go_test_file_unmodified():
    with open(os.path.join(CWD, "sanitizer_test.go"), "rb") as actual, open("/tmp/expected_sanitizer_test.go", "rb") as expected:
        assert actual.read() == expected.read(), "sanitizer_test.go was modified"


def test_strip_tags_behavior_and_memory_safety(tmp_path):
    harness = tmp_path / "sanitizer_harness.cpp"
    harness.write_text(textwrap.dedent(r'''
        #include <atomic>
        #include <cstdlib>
        #include <cstring>
        #include <random>
        #include <string>
        #include <thread>
        #include <vector>

        extern "C" char* strip_tags(const char* input);
        extern "C" void free_string(char* str);

        static std::string expected(const std::string& input) {
            std::string out;
            bool in_tag = false;
            for (char c : input) {
                if (c == '<') in_tag = true;
                else if (c == '>') in_tag = false;
                else if (!in_tag) out.push_back(c);
            }
            return out;
        }

        static bool check(const std::string& input) {
            const std::string want = expected(input);
            char* got_ptr = strip_tags(input.c_str());
            if (got_ptr == nullptr) return false;
            const bool ok = std::strcmp(got_ptr, want.c_str()) == 0;
            free_string(got_ptr);
            return ok;
        }

        int main() {
            const std::vector<std::string> fixed = {
                "", "plain text", "<b>Hello</b> <i>World</i>",
                "<script>alert(1)</script>", "An unfinished <tag",
                "<><><>", "left>right", "a<tag>b</tag>c"
            };
            for (const auto& value : fixed) if (!check(value)) return 10;

            std::mt19937 rng(0x51A17u);
            const std::string alphabet = "abc XYZ0123<>/'=!-";
            std::vector<std::string> cases;
            for (int n = 0; n < 300; ++n) {
                std::string value;
                const int length = static_cast<int>(rng() % 300);
                for (int i = 0; i < length; ++i)
                    value.push_back(alphabet[rng() % alphabet.size()]);
                cases.push_back(value);
                if (!check(value)) return 11;
            }

            std::atomic<bool> failed(false);
            std::vector<std::thread> threads;
            for (int t = 0; t < 12; ++t) {
                threads.emplace_back([&, t]() {
                    for (int i = 0; i < 400; ++i)
                        if (!check(cases[(i * 17 + t) % cases.size()])) failed = true;
                });
            }
            for (auto& thread : threads) thread.join();
            return failed ? 12 : 0;
        }
    '''), encoding="utf-8")

    executable = tmp_path / "sanitizer_harness"
    build = run([
        "g++", "-std=c++11", "-O1", "-g", "-fsanitize=address",
        "-fno-omit-frame-pointer", "-pthread",
        os.path.join(CWD, "sanitizer.cpp"), str(harness), "-o", str(executable),
    ], timeout=30)
    assert build.returncode == 0, f"Could not compile sanitizer.cpp with the verification harness.\nSTDOUT:\n{build.stdout}\nSTDERR:\n{build.stderr}"

    env = os.environ.copy()
    env["ASAN_OPTIONS"] = "detect_leaks=0:abort_on_error=1"
    result = run([str(executable)], timeout=30, env=env)
    assert result.returncode == 0, f"strip_tags produced incorrect output or failed AddressSanitizer checks (exit {result.returncode}).\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"


def test_go_tests_pass():
    assert os.path.isdir(CWD), f"Directory {CWD} does not exist."
    result = run(["go", "test"], cwd=CWD, timeout=30)
    assert result.returncode == 0, f"'go test' failed with exit code {result.returncode}.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"


def test_benchmark_really_runs():
    result = run(["go", "test", "-run", "^$", "-bench", "^BenchmarkSanitize$", "-count=1"], cwd=CWD, timeout=60)
    assert result.returncode == 0, f"The benchmark could not be executed.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    assert_benchmark_output(result.stdout + result.stderr)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
