#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
from pathlib import Path


def run_pipeline():
    return subprocess.run(
        ["/home/user/pipeline.sh"],
        capture_output=True,
        text=True,
        timeout=120,
    )


def test_pipeline_script_exists_and_executable():
    script_path = "/home/user/pipeline.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_makefile_contains_lm():
    makefile_path = "/home/user/project/Makefile"
    assert os.path.isfile(makefile_path), f"Makefile {makefile_path} does not exist."
    with open(makefile_path, "r") as f:
        content = f.read()
    assert "-lm" in content, "Makefile does not contain '-lm' for linking the math library."


def test_pipeline_execution_and_outputs():
    result = run_pipeline()
    assert result.returncode == 0, f"Pipeline script failed to execute. stderr: {result.stderr}"

    status_log_path = "/home/user/status.log"
    assert os.path.isfile(status_log_path), f"{status_log_path} does not exist."
    with open(status_log_path, "r") as f:
        status = f.read().strip()
    assert status == "PASS", f"Expected 'PASS' in {status_log_path}, but got '{status}'"

    asm_count_path = "/home/user/asm_line_count.txt"
    assert os.path.isfile(asm_count_path), f"{asm_count_path} does not exist."
    with open(asm_count_path, "r") as f:
        count_str = f.read().strip()
    count_val = count_str.split()[0] if count_str else ""
    assert count_val.isdigit(), f"{asm_count_path} does not contain a valid integer. Found: '{count_str}'"

    final_output_path = "/home/user/final_output.txt"
    expected_path = "/home/user/project/expected.txt"
    assert os.path.isfile(final_output_path), f"{final_output_path} does not exist."
    assert os.path.isfile(expected_path), f"{expected_path} does not exist."

    with open(final_output_path, "r") as f:
        final_content = f.read().strip()
    with open(expected_path, "r") as f:
        expected_content = f.read().strip()
    assert final_content == expected_content, "final_output.txt does not match expected.txt"


def test_z_pipeline_rebuilds_and_processes_derived_inputs():
    project = Path("/home/user/project")
    main_c = project / "main.c"
    analyzer_go = project / "analyzer.go"
    expected = project / "expected.txt"
    saved = {p: p.read_bytes() for p in (main_c, analyzer_go, expected)}

    dynamic_main = r'''#include <stdio.h>
#include <math.h>

int main(void) {
    volatile double values[] = {49.0, 121.0, 169.0};
    for (int i = 0; i < 3; ++i) {
        printf("%.6f\n", sqrt(values[i]));
    }
    return 0;
}
'''
    dynamic_analyzer = r'''package main

import (
    "bufio"
    "fmt"
    "os"
    "sync"
)

func main() {
    scanner := bufio.NewScanner(os.Stdin)
    results := make(chan string, 32)
    var wg sync.WaitGroup
    for scanner.Scan() {
        line := scanner.Text()
        wg.Add(1)
        go func(s string) {
            defer wg.Done()
            results <- fmt.Sprintf("Verified: %s", s)
        }(line)
    }
    go func() {
        wg.Wait()
        close(results)
    }()
    for result := range results {
        fmt.Println(result)
    }
}
'''
    c_text = "7.000000\n11.000000\n13.000000\n"
    sorted_text = "Verified: 11.000000\nVerified: 13.000000\nVerified: 7.000000\n"

    generated = [
        project / "main.o", project / "main", project / "main.s",
        project / "analyzer", Path("/home/user/asm_line_count.txt"),
        Path("/home/user/c_output.txt"), Path("/home/user/final_output.txt"),
        Path("/home/user/status.log"),
    ]

    try:
        main_c.write_text(dynamic_main)
        analyzer_go.write_text(dynamic_analyzer)
        expected.write_text(sorted_text)
        for path in generated:
            try:
                path.unlink()
            except FileNotFoundError:
                pass

        result = run_pipeline()
        assert result.returncode == 0, f"Pipeline failed on derived inputs: {result.stderr}"

        main_bin = project / "main"
        analyzer_bin = project / "analyzer"
        assembly = project / "main.s"
        assert main_bin.is_file() and main_bin.read_bytes()[:4] == b"\x7fELF", "make did not produce a native main executable"
        assert analyzer_bin.is_file() and analyzer_bin.read_bytes()[:4] == b"\x7fELF", "go build did not produce an analyzer executable"
        assert assembly.is_file(), "main.s was not generated"
        assembly_text = assembly.read_text(errors="replace")
        assert "main" in assembly_text and "sqrt" in assembly_text, "main.s is not assembly generated from the test main.c"

        main_result = subprocess.run([str(main_bin)], capture_output=True, text=True, timeout=30)
        assert main_result.returncode == 0
        assert main_result.stdout == c_text, "main executable was not rebuilt from main.c"
        assert Path("/home/user/c_output.txt").read_text() == c_text, "c_output.txt was not captured from main"

        count_text = Path("/home/user/asm_line_count.txt").read_text().strip()
        count_word = count_text.split()[0] if count_text else ""
        assert count_word.isdigit(), "assembly line count is not an integer"
        actual_lines = sum(1 for _ in assembly.open("rb"))
        assert int(count_word) == actual_lines, "asm_line_count.txt does not contain the actual main.s line count"

        analyzer_result = subprocess.run(
            [str(analyzer_bin)], input="zeta\nalpha\n", capture_output=True,
            text=True, timeout=30,
        )
        assert analyzer_result.returncode == 0
        assert sorted(analyzer_result.stdout.splitlines()) == ["Verified: alpha", "Verified: zeta"], \
            "analyzer was not built from analyzer.go or does not process stdin"

        assert Path("/home/user/final_output.txt").read_text() == sorted_text, \
            "pipeline did not run the analyzer and sort its derived output"
        assert Path("/home/user/status.log").read_text().strip() == "PASS"

        # A mismatching oracle must produce FAIL while leaving the analyzer-derived
        # final output intact; merely copying expected.txt cannot satisfy this.
        expected.write_text("INTENTIONAL MISMATCH\n")
        second = run_pipeline()
        assert second.returncode == 0, f"Pipeline did not handle a failed diff: {second.stderr}"
        assert Path("/home/user/final_output.txt").read_text() == sorted_text, \
            "final_output.txt was copied from expected.txt instead of generated"
        assert Path("/home/user/status.log").read_text().strip() == "FAIL", \
            "pipeline did not record FAIL when diff found a mismatch"
    finally:
        for path, content in saved.items():
            path.write_bytes(content)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
