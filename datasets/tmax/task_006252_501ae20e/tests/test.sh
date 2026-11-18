#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import re
import subprocess
import time

import pytest

WORK_DIR = "/home/user/url_router"
LOG_FILE = "/home/user/benchmark.log"
NUMERIC = re.compile(r"^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$")


def run(cmd, **kwargs):
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("text", True)
    kwargs.setdefault("timeout", 30)
    return subprocess.run(cmd, **kwargs)


def cpp_string(value):
    return json.dumps(value)


def expected_parse(url):
    if "?" not in url:
        path = url
        pieces = []
        hashed = url
    else:
        path, query = url.split("?", 1)
        hashed = path
        if query == "":
            pieces = []
        else:
            pieces = query.split("&")
            if query.endswith("&"):
                pieces.pop()

    params = {}
    for piece in pieces:
        if "=" in piece:
            key, value = piece.split("=", 1)
        else:
            key, value = piece, ""
        params[key] = value
        hashed += key + value

    checksum = 0
    for char in hashed:
        checksum = (checksum * 31 + ord(char)) & 0xffffffff
    return path, params, checksum


def test_make_all_succeeds_and_targets_run():
    run(["make", "clean"], cwd=WORK_DIR)
    result = run(["make", "all"], cwd=WORK_DIR)
    assert result.returncode == 0, f"make all failed. stderr:\n{result.stderr}\nstdout:\n{result.stdout}"

    app = os.path.join(WORK_DIR, "router_app")
    test = os.path.join(WORK_DIR, "router_test")
    assert os.path.isfile(app), "router_app executable was not built"
    assert os.path.isfile(test), "router_test executable was not built"
    assert os.access(app, os.X_OK), "router_app is not executable"
    assert os.access(test, os.X_OK), "router_test is not executable"

    result = run([test], cwd=WORK_DIR)
    assert result.returncode == 0, f"router_test failed:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"


def test_router_bug_fixed_on_derived_random_cases():
    rng = random.SystemRandom()
    alphabet = "abcXYZ019_-"
    urls = [
        "/api?key=",
        "/api?key",
        "/api?key=&other=1",
        "/?=value",
        "/?=",
        "/?&&x=1",
        "/?a=b=c&&missing&empty=",
        "/plain/path",
        "/?",
    ]

    for _ in range(350):
        path = "/" + "".join(rng.choice(alphabet) for _ in range(rng.randrange(0, 20)))
        if rng.randrange(8) == 0:
            urls.append(path)
            continue
        fields = []
        for _ in range(rng.randrange(0, 9)):
            key = "".join(rng.choice(alphabet) for _ in range(rng.randrange(0, 9)))
            kind = rng.randrange(4)
            if kind == 0:
                fields.append(key)  # missing '='
            elif kind == 1:
                fields.append(key + "=")  # explicitly empty value
            else:
                value = "".join(rng.choice(alphabet + "=") for _ in range(rng.randrange(0, 12)))
                fields.append(key + "=" + value)
        query = "&".join(fields)
        if rng.randrange(7) == 0:
            query += "&"
        urls.append(path + "?" + query)

    cases = []
    for url in urls:
        path, params, checksum = expected_parse(url)
        entries = ",".join("{" + cpp_string(k) + "," + cpp_string(v) + "}" for k, v in sorted(params.items()))
        cases.append(
            "{" + cpp_string(url) + "," + cpp_string(path) + ",std::map<std::string,std::string>{" + entries + "}," + str(checksum) + "u}"
        )

    source = r'''
#include "/home/user/url_router/router.h"
#include <map>
#include <string>
#include <vector>
#include <iostream>

struct Case {
    std::string url;
    std::string path;
    std::map<std::string, std::string> params;
    unsigned int checksum;
};

int main() {
    const std::vector<Case> cases = {
''' + ",\n".join(cases) + r'''
    };
    for (size_t i = 0; i < cases.size(); ++i) {
        try {
            RouteResult got = Router::parse(cases[i].url);
            if (got.path != cases[i].path || got.params != cases[i].params || got.checksum != cases[i].checksum) {
                std::cerr << "mismatch on generated case " << i << ": " << cases[i].url << "\n";
                return 1;
            }
        } catch (...) {
            std::cerr << "exception on generated case " << i << "\n";
            return 2;
        }
    }
    return 0;
}
'''
    with open("/tmp/verify_random.cpp", "w") as f:
        f.write(source)
    compiled = run(["g++", "-std=c++17", "/tmp/verify_random.cpp", os.path.join(WORK_DIR, "router.cpp"), "-o", "/tmp/verify_random"])
    assert compiled.returncode == 0, f"Failed to compile randomized parser check:\n{compiled.stderr}"
    checked = run(["/tmp/verify_random"])
    assert checked.returncode == 0, f"Parser failed randomized derived-oracle checks:\n{checked.stderr}"


def test_router_test_is_property_based_and_checks_results():
    probe = r'''
#include "/home/user/url_router/router.h"
#include <fstream>
#include <sstream>
#include <cstdlib>

unsigned int Router::computeChecksum(const std::string& data) {
    unsigned int hash = 0;
    for (unsigned char c : data) hash = hash * 31 + c;
    return hash;
}

RouteResult Router::parse(const std::string& url) {
    if (const char* log = std::getenv("ROUTER_PROBE_LOG")) {
        std::ofstream out(log, std::ios::app);
        out << url << '\n';
    }
    RouteResult result;
    size_t q = url.find('?');
    if (q == std::string::npos) {
        result.path = url;
        result.checksum = computeChecksum(url);
        return result;
    }
    result.path = url.substr(0, q);
    std::string query = url.substr(q + 1), pair, to_hash = result.path;
    std::stringstream ss(query);
    while (std::getline(ss, pair, '&')) {
        size_t eq = pair.find('=');
        std::string key = eq == std::string::npos ? pair : pair.substr(0, eq);
        std::string value = eq == std::string::npos ? "" : pair.substr(eq + 1);
        result.params[key] = value;
        to_hash += key + value;
    }
    result.checksum = computeChecksum(to_hash);
    return result;
}
'''
    with open("/tmp/router_probe.cpp", "w") as f:
        f.write(probe)
    built = run(["g++", "-std=c++17", os.path.join(WORK_DIR, "test.cpp"), "/tmp/router_probe.cpp", "-o", "/tmp/probed_router_test"])
    assert built.returncode == 0, f"Could not instrument test.cpp:\n{built.stderr}"

    probe_log = "/tmp/router_probe_urls.log"
    if os.path.exists(probe_log):
        os.remove(probe_log)
    env = os.environ.copy()
    env["ROUTER_PROBE_LOG"] = probe_log
    tested = run(["/tmp/probed_router_test"], cwd=WORK_DIR, env=env)
    assert tested.returncode == 0, f"test.cpp fails with a correct parser:\n{tested.stderr}"
    assert os.path.isfile(probe_log), "router_test did not call Router::parse"
    with open(probe_log) as f:
        urls = [line.rstrip("\n") for line in f]

    assert len(urls) >= 50, "test.cpp must fuzz Router::parse with many generated inputs"
    assert len(set(urls)) >= 20, "test.cpp does not generate sufficiently varied query strings"
    assert len({len(url) for url in urls}) >= 5, "fuzzed URLs do not vary in length"
    queries = [url.split("?", 1)[1] for url in urls if "?" in url]
    fields = [field for query in queries for field in query.split("&")]
    assert any("=" not in field for field in fields), "fuzzing does not cover parameters missing values"
    assert any(field.endswith("=") for field in fields), "fuzzing does not cover explicit empty values"
    assert any(field.startswith("=") for field in fields), "fuzzing does not cover empty keys"

    mutant = r'''
#include "/home/user/url_router/router.h"
#include <sstream>
unsigned int Router::computeChecksum(const std::string&) { return 0; }
RouteResult Router::parse(const std::string& url) {
    RouteResult r;
    r.path = "WRONG";
    size_t q = url.find('?');
    if (q != std::string::npos) {
        std::stringstream ss(url.substr(q + 1));
        std::string p;
        while (std::getline(ss, p, '&')) {
            size_t e = p.find('=');
            r.params[e == std::string::npos ? p : p.substr(0, e)] = "WRONG";
        }
    }
    return r;
}
'''
    with open("/tmp/router_mutant.cpp", "w") as f:
        f.write(mutant)
    built = run(["g++", "-std=c++17", os.path.join(WORK_DIR, "test.cpp"), "/tmp/router_mutant.cpp", "-o", "/tmp/mutant_router_test"])
    assert built.returncode == 0, f"Could not mutation-test test.cpp:\n{built.stderr}"
    rejected = run(["/tmp/mutant_router_test"], cwd=WORK_DIR)
    assert rejected.returncode != 0, "test.cpp generates inputs but does not detect an intentionally incorrect parser"


def test_benchmark_functionality_and_real_parse_loop():
    app = os.path.join(WORK_DIR, "router_app")
    assert os.path.isfile(app), "router_app must be built before testing benchmark"
    if os.path.exists(LOG_FILE):
        os.remove(LOG_FILE)
    result = run([app, "bench"], cwd=WORK_DIR)
    assert result.returncode == 0, f"router_app bench failed. stderr:\n{result.stderr}"
    assert os.path.isfile(LOG_FILE), f"Benchmark log file {LOG_FILE} was not created"
    with open(LOG_FILE) as f:
        content = f.read().strip()
    assert NUMERIC.fullmatch(content), f"Benchmark log does not contain only a numeric value: {content!r}"
    value = float(content)
    assert math.isfinite(value) and value >= 0, "Benchmark duration should be a finite non-negative number"

    benchmark_probe = r'''
#include "/home/user/url_router/router.h"
#include <chrono>
#include <fstream>
#include <string>
#include <thread>

static unsigned long calls = 0;
static unsigned long wrong = 0;
struct Reporter {
    ~Reporter() {
        std::ofstream out("/tmp/benchmark_probe_count");
        out << calls << " " << wrong;
    }
} reporter;

unsigned int Router::computeChecksum(const std::string&) { return 0; }
RouteResult Router::parse(const std::string& url) {
    ++calls;
    if (url != "/api/v1/data?id=999&checksum=a1b2&flags=active&mode=") ++wrong;
    if (calls == 1) std::this_thread::sleep_for(std::chrono::milliseconds(300));
    return RouteResult{};
}
'''
    with open("/tmp/benchmark_probe.cpp", "w") as f:
        f.write(benchmark_probe)
    built = run(["g++", "-std=c++17", os.path.join(WORK_DIR, "main.cpp"), "/tmp/benchmark_probe.cpp", "-pthread", "-o", "/tmp/probed_router_app"])
    assert built.returncode == 0, f"Could not instrument main.cpp benchmark:\n{built.stderr}"

    for path in (LOG_FILE, "/tmp/benchmark_probe_count"):
        if os.path.exists(path):
            os.remove(path)
    start = time.monotonic()
    result = run(["/tmp/probed_router_app", "bench"], cwd=WORK_DIR)
    wall_ms = (time.monotonic() - start) * 1000
    assert result.returncode == 0, f"Instrumented benchmark failed:\n{result.stderr}"
    assert os.path.isfile("/tmp/benchmark_probe_count"), "benchmark did not complete normally"
    with open("/tmp/benchmark_probe_count") as f:
        calls, wrong = map(int, f.read().split())
    assert calls == 100000, f"benchmark called Router::parse {calls} times instead of 100000"
    assert wrong == 0, "benchmark parsed a URL other than the required benchmark URL"
    assert os.path.isfile(LOG_FILE), "instrumented benchmark did not create benchmark.log"
    with open(LOG_FILE) as f:
        content = f.read().strip()
    assert NUMERIC.fullmatch(content), f"benchmark.log contains non-numeric content: {content!r}"
    measured_ms = float(content)
    assert math.isfinite(measured_ms)
    assert measured_ms >= 200, "reported duration does not include time spent in Router::parse"
    assert measured_ms <= wall_ms + 1000, "reported benchmark duration is not in milliseconds"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
