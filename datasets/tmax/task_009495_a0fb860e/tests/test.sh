#!/bin/bash
set -e
mkdir -p /logs/verifier

verify() {
    cd /home/user/math_vm

    test -f vm.c
    test -f Makefile
    test -f pyvm.py
    test -f test_vm.py

    # Rebuild the submitted artifact rather than trusting a pre-existing library.
    rm -f libvm.so
    make
    test -f libvm.so

    # Trace actual calls made by test_vm.py so a pre-created success log cannot pass.
    rm -f test_success.log /tmp/vm_calls.jsonl
    rm -rf /tmp/vm_trace
    mkdir -p /tmp/vm_trace
    cat > /tmp/vm_trace/sitecustomize.py <<'PYEOF'
import json
import pyvm

_trace_path = "/tmp/vm_calls.jsonl"

def _wrap(name, original):
    def traced(instructions):
        try:
            seq = [[int(op), int(value)] for op, value in instructions]
        except Exception:
            seq = repr(instructions)
        with open(_trace_path, "a") as trace:
            trace.write(json.dumps({"fn": name, "seq": seq}, sort_keys=True) + "\n")
        return original(instructions)
    return traced

pyvm.execute_py = _wrap("py", pyvm.execute_py)
pyvm.execute_c = _wrap("c", pyvm.execute_c)
PYEOF

    timeout 180s env PYTHONPATH="/tmp/vm_trace${PYTHONPATH:+:$PYTHONPATH}" python3 test_vm.py

    cat > /tmp/check_property_test.py <<'PYEOF'
import ast
import json
import os

base = "/home/user/math_vm"
script_path = os.path.join(base, "test_vm.py")
log_path = os.path.join(base, "test_success.log")
trace_path = "/tmp/vm_calls.jsonl"

assert os.path.isfile(script_path), "test_vm.py is missing"
source = open(script_path, encoding="utf-8").read()
tree = ast.parse(source, filename=script_path)

imports_hypothesis = False
names = set()
strings = set()
for node in ast.walk(tree):
    if isinstance(node, ast.Import):
        imports_hypothesis |= any(alias.name == "hypothesis" or alias.name.startswith("hypothesis.") for alias in node.names)
    elif isinstance(node, ast.ImportFrom):
        imports_hypothesis |= node.module == "hypothesis" or (node.module or "").startswith("hypothesis.")
    elif isinstance(node, ast.Name):
        names.add(node.id)
    elif isinstance(node, ast.Attribute):
        names.add(node.attr)
    elif isinstance(node, ast.Constant) and isinstance(node.value, str):
        strings.add(node.value)

assert imports_hypothesis, "test_vm.py must use Hypothesis"
assert "given" in names, "test_vm.py does not define a Hypothesis @given property"
assert "execute_py" in names and "execute_c" in names, "the property must call both VM implementations"
assert "ValueError" in names, "the property must check ValueError behavior"
assert "PROPERTY_TESTS_PASSED" in strings, "the required success marker is absent from test_vm.py"

assert os.path.isfile(log_path), "test_vm.py did not create test_success.log"
with open(log_path, encoding="utf-8") as f:
    assert f.read().strip() == "PROPERTY_TESTS_PASSED", "incorrect success-log content"

assert os.path.isfile(trace_path), "test_vm.py did not call the VM implementations"
records = []
with open(trace_path, encoding="utf-8") as f:
    for line in f:
        if line.strip():
            records.append(json.loads(line))

py_sequences = [r["seq"] for r in records if r.get("fn") == "py"]
c_sequences = [r["seq"] for r in records if r.get("fn") == "c"]
assert py_sequences and c_sequences, "the property test must execute both implementations"

def key(seq):
    return json.dumps(seq, sort_keys=True)

py_unique = {key(s) for s in py_sequences}
c_unique = {key(s) for s in c_sequences}
assert len(py_unique) >= 5, "the property test did not exercise varied generated sequences"
assert len(py_unique & c_unique) >= 5, "both implementations were not exercised on the same generated inputs"

for seq in py_sequences + c_sequences:
    assert isinstance(seq, list), "instructions must be lists of tuples/pairs"
    for item in seq:
        assert isinstance(item, list) and len(item) == 2, "each instruction must be an opcode/value pair"
        op, value = item
        assert 0 <= op <= 3, "generated opcode is outside 0..3"
        assert -1000 <= value <= 1000, "generated value is outside -1000..1000"
PYEOF
    python3 /tmp/check_property_test.py

    # Compile vm.c independently, preventing a Makefile from substituting another implementation.
    gcc -shared -fPIC -fwrapv -O2 -o /tmp/libvm_candidate.so vm.c

    cat > /tmp/check_vm_behavior.py <<'PYEOF'
import ctypes
import os
import random

class Instruction(ctypes.Structure):
    _fields_ = [("opcode", ctypes.c_int), ("value", ctypes.c_int)]

INT_MIN = -(2**31)
INT_MAX = 2**31 - 1
rng = random.SystemRandom()

def load(path):
    assert os.path.isfile(path), f"missing library: {path}"
    lib = ctypes.CDLL(path)
    fn = lib.execute_vm
    fn.argtypes = [ctypes.POINTER(Instruction), ctypes.c_int, ctypes.POINTER(ctypes.c_int)]
    fn.restype = ctypes.c_int
    return fn

def reference(seq):
    stack = []
    for op, value in seq:
        if op == 0:
            stack.append(value)
            continue
        if len(stack) < 2:
            raise ValueError
        b = stack.pop()
        a = stack.pop()
        if op == 1:
            value = a + b
        elif op == 2:
            value = a - b
        elif op == 3:
            value = a * b
        else:
            raise ValueError
        if not INT_MIN <= value <= INT_MAX:
            raise OverflowError
        stack.append(value)
    if len(stack) != 1:
        raise ValueError
    return stack[0]

def run(fn, seq):
    arr = (Instruction * len(seq))()
    for i, (op, value) in enumerate(seq):
        arr[i].opcode = op
        arr[i].value = value
    result = ctypes.c_int()
    status = fn(arr, len(seq), ctypes.byref(result))
    return status, result.value

def valid_sequence():
    seq = []
    values = []
    for _ in range(rng.randint(1, 160)):
        if len(values) < 2 or rng.random() < 0.58:
            value = rng.randint(-1000, 1000)
            seq.append((0, value))
            values.append(value)
        else:
            a, b = values[-2], values[-1]
            choices = []
            for op, result in ((1, a + b), (2, a - b), (3, a * b)):
                if INT_MIN <= result <= INT_MAX:
                    choices.append((op, result))
            if not choices:
                continue
            op, result = rng.choice(choices)
            seq.append((op, rng.randint(-1000, 1000)))
            values[-2:] = [result]
    while len(values) > 1:
        a, b = values[-2], values[-1]
        choices = []
        for op, result in ((1, a + b), (2, a - b), (3, a * b)):
            if INT_MIN <= result <= INT_MAX:
                choices.append((op, result))
        if not choices:
            # Push zero and safely consume it before trying the reduction again.
            seq.extend([(0, 0), (1, 0)])
            continue
        op, result = rng.choice(choices)
        seq.append((op, rng.randint(-1000, 1000)))
        values[-2:] = [result]
    return seq

cases = [
    [],
    [(1, 0)],
    [(0, 1), (0, 2)],
    [(0, -7)],
    [(0, 9), (0, 4), (2, 0)],
    [(0, 7), (0, -3), (3, 0)],
]

# Preserve the original fixed overflow regression test.
num_pushes = 100
cases.append([(0, 1)] * num_pushes + [(1, 0)] * (num_pushes - 1))

# Exercise much larger stacks and randomized valid and invalid programs.
cases.append([(0, 1)] * 50000 + [(1, 0)] * 49999)
for _ in range(250):
    cases.append(valid_sequence())
for _ in range(250):
    length = rng.randint(0, 180)
    cases.append([(rng.randint(0, 3), rng.randint(-1000, 1000)) for _ in range(length)])

for library_path in ("/home/user/math_vm/libvm.so", "/tmp/libvm_candidate.so"):
    fn = load(library_path)
    for seq in cases:
        try:
            expected = reference(seq)
        except OverflowError:
            continue
        except ValueError:
            status, _ = run(fn, seq)
            assert status != 0, f"{library_path} accepted invalid program {seq[:20]!r}"
        else:
            status, actual = run(fn, seq)
            assert status == 0, f"{library_path} rejected valid program {seq[:20]!r}"
            assert actual == expected, f"{library_path}: expected {expected}, got {actual}"
PYEOF
    timeout 120s python3 /tmp/check_vm_behavior.py

    # AddressSanitizer/LeakSanitizer checks real execution paths for overflows,
    # use-after-free, and allocations left reachable at process exit.
    cat > /tmp/vm_sanitizer_harness.c <<'CEOF'
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

typedef struct {
    int opcode;
    int value;
} Instruction;

extern int execute_vm(Instruction *instrs, int count, int *result);

static uint32_t state;
static uint32_t next_random(void) {
    state ^= state << 13;
    state ^= state >> 17;
    state ^= state << 5;
    return state;
}

static int run_sum(int pushes) {
    int count = pushes * 2 - 1;
    Instruction *instructions = malloc((size_t)count * sizeof(*instructions));
    if (!instructions) return 20;
    for (int i = 0; i < pushes; ++i) {
        instructions[i].opcode = 0;
        instructions[i].value = 1;
    }
    for (int i = pushes; i < count; ++i) {
        instructions[i].opcode = 1;
        instructions[i].value = 0;
    }
    int result = 0;
    int status = execute_vm(instructions, count, &result);
    free(instructions);
    return status == 0 && result == pushes ? 0 : 21;
}

int main(void) {
    FILE *random_file = fopen("/dev/urandom", "rb");
    if (random_file) {
        if (fread(&state, sizeof(state), 1, random_file) != 1) state = 0x91a2b3c4u;
        fclose(random_file);
    } else {
        state = 0x91a2b3c4u;
    }

    if (run_sum(50000)) return 1;

    for (int i = 0; i < 3000; ++i) {
        int pushes = 1 + (int)(next_random() % 1500u);
        if (run_sum(pushes)) return 2;

        Instruction underflow[1] = {{1 + (int)(next_random() % 3u), 0}};
        int result = 0;
        if (execute_vm(underflow, 1, &result) == 0) return 3;

        Instruction leftover[2] = {{0, 1}, {0, 2}};
        if (execute_vm(leftover, 2, &result) == 0) return 4;
    }
    return 0;
}
CEOF

    gcc -fwrapv -O1 -g -fsanitize=address -fno-omit-frame-pointer \
        -o /tmp/vm_sanitizer vm.c /tmp/vm_sanitizer_harness.c
    timeout 120s env ASAN_OPTIONS="detect_leaks=1:halt_on_error=1:exitcode=99" \
        /tmp/vm_sanitizer
}

if verify; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
