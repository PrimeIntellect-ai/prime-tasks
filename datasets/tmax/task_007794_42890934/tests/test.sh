#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
from pathlib import Path


def test_go_mod_exists():
    go_mod_path = "/home/user/go.mod"
    assert os.path.exists(go_mod_path), f"The file {go_mod_path} is missing. Did you initialize the Go module?"
    with open(go_mod_path, "r") as f:
        content = f.read()
    assert "module webfeature" in content, f"The file {go_mod_path} does not contain 'module webfeature'."


def test_journey_go_exists():
    journey_go_path = "/home/user/journey.go"
    assert os.path.exists(journey_go_path), f"The file {journey_go_path} is missing."
    assert os.path.isfile(journey_go_path), f"The path {journey_go_path} is not a file."


def test_completed_users_txt():
    completed_users_path = "/home/user/completed_users.txt"
    assert os.path.exists(completed_users_path), f"The file {completed_users_path} is missing."

    expected_users = ["user_b", "user_c", "user_e"]

    with open(completed_users_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert lines == expected_users, f"The content of {completed_users_path} is incorrect. Expected {expected_users}, but got {lines}."


def test_journey_test_go_exists():
    journey_test_go_path = "/home/user/journey_test.go"
    assert os.path.exists(journey_test_go_path), f"The file {journey_test_go_path} is missing. Did you write the benchmark test?"
    assert os.path.isfile(journey_test_go_path), f"The path {journey_test_go_path} is not a file."


def test_bench_txt():
    bench_txt_path = "/home/user/bench.txt"
    assert os.path.exists(bench_txt_path), f"The file {bench_txt_path} is missing. Did you run the benchmark and redirect output?"

    with open(bench_txt_path, "r") as f:
        content = f.read()

    assert "Benchmark" in content, f"The file {bench_txt_path} does not seem to contain standard Go benchmark output."
    assert re.search(r"(?m)^Benchmark\S*\s+\d+", content), f"The file {bench_txt_path} does not contain a Go benchmark result line."

    result = subprocess.run(
        ["go", "test", "-run", "^$", "-bench", ".", "-benchtime=1x"],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=60,
    )
    assert result.returncode == 0, f"The Go benchmark does not compile or run:\n{result.stdout}"
    assert re.search(r"(?m)^Benchmark\S*\s+\d+", result.stdout), f"No runnable benchmark was found:\n{result.stdout}"


def expected_completed(events):
    states = {}
    completed = set()
    for user, event in events:
        state = states.get(user, 0)
        if event == "LOGIN":
            state = 1
        elif event == "VIEW_ITEM" and state == 1:
            state = 2
        elif event == "ADD_CART" and state == 2:
            state = 3
        elif event == "CHECKOUT" and state == 3:
            state = 4
            completed.add(user)
        elif event == "LOGOUT":
            state = 0
        states[user] = state
    return sorted(completed)


def test_program_execution_and_state_machine():
    events_path = Path("/home/user/events.log")
    completed_path = Path("/home/user/completed_users.txt")
    original_events = events_path.read_bytes()
    original_completed = completed_path.read_bytes()

    prefix = "verify_" + secrets.token_hex(8)
    fixed_case = [
        (prefix + "_a", "LOGIN"),
        (prefix + "_b", "LOGIN"),
        (prefix + "_a", "VIEW_ITEM"),
        (prefix + "_b", "VIEW_ITEM"),
        (prefix + "_a", "ADD_CART"),
        (prefix + "_b", "VIEW_ITEM"),
        (prefix + "_a", "CHECKOUT"),
        (prefix + "_a", "LOGOUT"),
        (prefix + "_b", "ADD_CART"),
        (prefix + "_b", "CHECKOUT"),
        (prefix + "_c", "LOGIN"),
        (prefix + "_c", "VIEW_ITEM"),
        (prefix + "_c", "ADD_CART"),
        (prefix + "_c", "LOGIN"),
        (prefix + "_c", "CHECKOUT"),
        (prefix + "_d", "LOGIN"),
        (prefix + "_d", "VIEW_ITEM"),
        (prefix + "_d", "LOGOUT"),
        (prefix + "_d", "ADD_CART"),
        (prefix + "_d", "CHECKOUT"),
        (prefix + "_e", "VIEW_ITEM"),
        (prefix + "_e", "LOGIN"),
        (prefix + "_e", "ADD_CART"),
        (prefix + "_e", "VIEW_ITEM"),
        (prefix + "_e", "CHECKOUT"),
    ]

    incomplete_case = [
        (prefix + "_x", "VIEW_ITEM"),
        (prefix + "_x", "ADD_CART"),
        (prefix + "_x", "CHECKOUT"),
        (prefix + "_y", "LOGIN"),
        (prefix + "_y", "VIEW_ITEM"),
        (prefix + "_y", "LOGOUT"),
        (prefix + "_y", "ADD_CART"),
        (prefix + "_z", "LOGIN"),
        (prefix + "_z", "CHECKOUT"),
    ]

    random_users = [prefix + "_r_" + secrets.token_hex(4) for _ in range(24)]
    event_types = ["LOGIN", "VIEW_ITEM", "ADD_CART", "CHECKOUT", "LOGOUT"]
    random_case = []
    for _ in range(500):
        random_case.append((secrets.choice(random_users), secrets.choice(event_types)))
    for user in random_users[:4]:
        random_case.extend([(user, "LOGIN"), (user, "VIEW_ITEM"), (user, "ADD_CART"), (user, "CHECKOUT")])

    try:
        for events in (fixed_case, incomplete_case, random_case):
            events_path.write_text("".join(f"{user},{event}\n" for user, event in events))
            if completed_path.exists():
                completed_path.unlink()

            result = subprocess.run(
                ["go", "run", "/home/user/journey.go"],
                cwd="/home/user",
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                timeout=30,
            )
            assert result.returncode == 0, f"journey.go failed to compile or run:\n{result.stdout}"
            assert completed_path.is_file(), "journey.go did not generate /home/user/completed_users.txt"
            actual = [line.strip() for line in completed_path.read_text().splitlines() if line.strip()]
            expected = expected_completed(events)
            assert actual == expected, f"State-machine output was incorrect. Expected {expected}, got {actual}."
    finally:
        events_path.write_bytes(original_events)
        completed_path.write_bytes(original_completed)


def test_journey_uses_go_concurrency():
    checker = r'''
package main
import (
    "fmt"
    "go/ast"
    "go/parser"
    "go/token"
    "os"
)
func main() {
    f, err := parser.ParseFile(token.NewFileSet(), "/home/user/journey.go", nil, 0)
    if err != nil { fmt.Fprintln(os.Stderr, err); os.Exit(1) }
    found := false
    ast.Inspect(f, func(n ast.Node) bool {
        if _, ok := n.(*ast.GoStmt); ok { found = true }
        return true
    })
    if !found { fmt.Fprintln(os.Stderr, "journey.go contains no goroutine (go statement)"); os.Exit(1) }
}
'''
    Path("/tmp/check_journey_concurrency.go").write_text(checker)
    result = subprocess.run(
        ["go", "run", "/tmp/check_journey_concurrency.go"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=30,
    )
    assert result.returncode == 0, f"journey.go does not use Go concurrency as required:\n{result.stdout}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
