#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pathlib
import subprocess
import tempfile

WORKSPACE = pathlib.Path('/home/user/uptime_monitor')
REPORT = pathlib.Path('/home/user/uptime_report.json')

CANONICAL_LOG = '''[2023-12-15] API_GATEWAY 200
[2024-02-29] AUTH_SERVICE 500
[2023-12-31] DATABASE SERVER 200
[2023-11-30] API_GATEWAY 200
[2024-02-29] DATABASE SERVER 503
[2023-08-15] WEB APP 200
'''

EXPECTED_STATS = {
    'API_GATEWAY': {'200': 2},
    'AUTH_SERVICE': {'500': 1},
    'DATABASE SERVER': {'200': 1, '503': 1},
    'WEB APP': {'200': 1},
}


def run(cmd, *, cwd=None, env=None, timeout=60):
    result = subprocess.run(
        cmd,
        cwd=cwd,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )
    assert result.returncode == 0, (
        f"Command failed ({result.returncode}): {' '.join(map(str, cmd))}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def test_fuzzer_exists():
    assert os.path.isfile(WORKSPACE / 'fuzzer.cpp'), 'fuzzer.cpp is missing. Did you write the libFuzzer target?'


def test_uptime_report_exists():
    assert os.path.isfile(REPORT), '/home/user/uptime_report.json is missing. Did you redirect the output?'


def test_uptime_report_content():
    log_file = WORKSPACE / 'production.log'
    assert os.path.isfile(log_file), f'{log_file} is missing.'
    try:
        actual_stats = json.loads(REPORT.read_text())
    except json.JSONDecodeError as exc:
        raise AssertionError(f'{REPORT} does not contain valid JSON: {exc}')
    assert actual_stats == EXPECTED_STATS, (
        f'The contents of {REPORT} do not match the expected statistics.\n'
        f'Expected: {EXPECTED_STATS}\nActual: {actual_stats}'
    )


def test_parser_date_boundaries_and_service_names():
    harness = r'''
#include "parser.h"
#include <cstdlib>
#include <iostream>
#include <stdexcept>
#include <string>

static void fail(const std::string& message) {
    std::cerr << message << std::endl;
    std::exit(1);
}

static void expect_ok(const std::string& line, int year, int month, int day,
                      const std::string& service, int status) {
    try {
        LogEntry entry = ParseLogLine(line);
        if (entry.year != year || entry.month != month || entry.day != day ||
            entry.service_name != service || entry.status_code != status) {
            fail("Incorrect parse for: " + line);
        }
    } catch (const std::exception& e) {
        fail("Unexpected exception for " + line + ": " + e.what());
    }
}

static void expect_bad(const std::string& line) {
    try {
        (void)ParseLogLine(line);
    } catch (const std::exception&) {
        return;
    }
    fail("Invalid date was accepted: " + line);
}

int main() {
    const int month_ends[] = {31,28,31,30,31,30,31,31,30,31,30,31};
    for (int month = 1; month <= 12; ++month) {
        char line[128];
        std::snprintf(line, sizeof(line), "[2023-%02d-%02d] SERVICE 200", month, month_ends[month-1]);
        expect_ok(line, 2023, month, month_ends[month-1], "SERVICE", 200);
    }

    expect_ok("[2024-02-29] AUTH SERVICE 500", 2024, 2, 29, "AUTH SERVICE", 500);
    expect_ok("[2000-02-29] DATABASE SERVER 503", 2000, 2, 29, "DATABASE SERVER", 503);
    expect_ok("[2023-12-31] WEB SERVER 200", 2023, 12, 31, "WEB SERVER", 200);
    expect_ok("[2023-08-15] A B C 204", 2023, 8, 15, "A B C", 204);

    expect_bad("[2023-00-01] SERVICE 200");
    expect_bad("[2023-13-01] SERVICE 200");
    expect_bad("[2023-02-29] SERVICE 200");
    expect_bad("[1900-02-29] SERVICE 200");
    expect_bad("[2024-02-30] SERVICE 200");
    expect_bad("[2023-04-31] SERVICE 200");
    expect_bad("[2023-12-00] SERVICE 200");
    expect_bad("[2023-12-32] SERVICE 200");
    return 0;
}
'''
    harness_path = pathlib.Path('/tmp/parser_harness.cpp')
    binary_path = pathlib.Path('/tmp/parser_harness')
    harness_path.write_text(harness)
    run([
        'clang++', '-std=c++17', '-fsanitize=address,undefined', '-g', '-O1',
        '-I', str(WORKSPACE), str(harness_path), str(WORKSPACE / 'parser.cpp'),
        '-o', str(binary_path),
    ])
    env = os.environ.copy()
    env['ASAN_OPTIONS'] = 'detect_leaks=0:abort_on_error=1'
    run([str(binary_path)], env=env)


def test_main_program_on_trusted_log():
    with tempfile.TemporaryDirectory(prefix='uptime-main-') as tmp:
        tmp_path = pathlib.Path(tmp)
        binary = tmp_path / 'uptime_monitor'
        (tmp_path / 'production.log').write_text(CANONICAL_LOG)
        run([
            'g++', '-std=c++17', str(WORKSPACE / 'main.cpp'),
            str(WORKSPACE / 'parser.cpp'), '-o', str(binary),
        ])
        result = run([str(binary)], cwd=tmp_path)
        try:
            actual = json.loads(result.stdout)
        except json.JSONDecodeError as exc:
            raise AssertionError(f'Compiled main program emitted invalid JSON: {exc}\n{result.stdout}')
        assert actual == EXPECTED_STATS, (
            f'Compiled main program produced incorrect statistics.\n'
            f'Expected: {EXPECTED_STATS}\nActual: {actual}'
        )


def test_fuzzer_compiles_runs_and_calls_parser():
    fuzzer_binary = pathlib.Path('/tmp/fuzzer_bin')
    run([
        'clang++', '-fsanitize=fuzzer,address', '-g', '-O1',
        str(WORKSPACE / 'fuzzer.cpp'), str(WORKSPACE / 'parser.cpp'),
        '-o', str(fuzzer_binary),
    ])

    corpus = pathlib.Path('/tmp/uptime_fuzz_corpus')
    corpus.mkdir(exist_ok=True)
    seeds = [
        b'[2024-02-29] WEB SERVER 200',
        b'[2023-12-31] DATABASE SERVER 503',
        b'[2023-02-29] INVALID 500',
        b'[2023-13-01] BAD MONTH 200',
        b'',
        b'not a log line',
    ]
    for index, seed in enumerate(seeds):
        (corpus / f'seed{index}').write_bytes(seed)

    env = os.environ.copy()
    env['ASAN_OPTIONS'] = 'detect_leaks=0:abort_on_error=1'
    run([str(fuzzer_binary), '-runs=200', '-max_len=128', str(corpus)], env=env, timeout=60)

    # Link the submitted target to an instrumented ParseLogLine implementation.
    # This ensures it actually invokes ParseLogLine rather than merely defining a
    # placeholder LLVMFuzzerTestOneInput function.
    stub_source = pathlib.Path('/tmp/parser_call_stub.cpp')
    stub_source.write_text(r'''
#include "parser.h"
#include <cstdlib>
#include <fstream>
LogEntry ParseLogLine(const std::string&) {
    const char* marker = std::getenv("FUZZ_PARSE_MARKER");
    if (marker) {
        std::ofstream out(marker, std::ios::app);
        out << "called\n";
    }
    return LogEntry{1970, 1, 1, "STUB", 200};
}
''')
    call_binary = pathlib.Path('/tmp/fuzzer_call_check')
    marker = pathlib.Path('/tmp/fuzzer_parse_called')
    marker.unlink(missing_ok=True)
    run([
        'clang++', '-fsanitize=fuzzer,address', '-g', '-O1',
        '-I', str(WORKSPACE), str(WORKSPACE / 'fuzzer.cpp'), str(stub_source),
        '-o', str(call_binary),
    ])
    call_env = env.copy()
    call_env['FUZZ_PARSE_MARKER'] = str(marker)
    run([str(call_binary), '-runs=1', str(corpus)], env=call_env, timeout=30)
    assert marker.is_file() and marker.stat().st_size > 0, (
        'The submitted libFuzzer target did not call ParseLogLine.'
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
