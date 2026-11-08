#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import stat
import subprocess
import tempfile

WORK = "/home/user/semver-resolve"
SOURCE = os.path.join(WORK, "resolve.c")
RUN_SH = os.path.join(WORK, "run.sh")
AVAIL = os.path.join(WORK, "available.txt")
CONST = os.path.join(WORK, "constraints.txt")
OUT = "/home/user/resolved_version.txt"


def parse_semver(v):
    parts = v.strip().split('.')
    assert len(parts) == 3
    return tuple(map(int, parts))


def expected_result(available, constraints):
    valid = []
    for version in available:
        parsed = parse_semver(version)
        ok = True
        for op, target in constraints:
            target_parsed = parse_semver(target)
            if op == ">=" and not parsed >= target_parsed:
                ok = False
            elif op == "<=" and not parsed <= target_parsed:
                ok = False
            elif op == ">" and not parsed > target_parsed:
                ok = False
            elif op == "<" and not parsed < target_parsed:
                ok = False
            elif op == "==" and not parsed == target_parsed:
                ok = False
            elif op == "!=" and not parsed != target_parsed:
                ok = False
        if ok:
            valid.append(version)
    return max(valid, key=parse_semver) if valid else "None"


def assert_original_output():
    assert os.path.exists(OUT), f"Output file not found: {OUT}"
    assert os.path.exists(AVAIL), f"Available versions file missing: {AVAIL}"
    assert os.path.exists(CONST), f"Constraints file missing: {CONST}"

    with open(AVAIL, 'r', encoding='utf-8') as f:
        available = [line.strip() for line in f if line.strip()]
    with open(CONST, 'rb') as f:
        raw_constraints = f.read()

    try:
        if b'\x00' in raw_constraints:
            text_constraints = raw_constraints.decode('utf-16le')
        else:
            text_constraints = raw_constraints.decode('utf-8')
    except UnicodeDecodeError:
        text_constraints = raw_constraints.decode('utf-8', errors='ignore')

    constraints = []
    for line in text_constraints.splitlines():
        parts = line.strip().split()
        if len(parts) == 2:
            constraints.append((parts[0], parts[1]))

    expected = expected_result(available, constraints)
    with open(OUT, 'r', encoding='utf-8') as f:
        actual = f.read().strip()
    assert actual == expected, (
        f"Incorrect resolved version. Expected '{expected}' based on constraints, "
        f"but got '{actual}'."
    )


def write_case(available, constraints, utf16):
    with open(AVAIL, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(available) + '\n')
    text = '\r\n'.join(f"{op} {target}" for op, target in constraints) + '\r\n'
    if utf16:
        with open(CONST, 'wb') as f:
            f.write(text.encode('utf-16le'))
    else:
        with open(CONST, 'w', encoding='utf-8', newline='') as f:
            f.write(text)


def run_and_check(command, expected, allow_output_file):
    if allow_output_file and os.path.exists(OUT):
        os.unlink(OUT)
    proc = subprocess.run(
        command, cwd=WORK, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=15, env=os.environ.copy()
    )
    assert proc.returncode == 0, (
        f"Command failed ({proc.returncode}): {' '.join(command)}\n"
        f"stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
    )
    lines = [line.strip() for line in proc.stdout.splitlines() if line.strip()]
    if lines:
        actual = lines[-1]
    elif allow_output_file and os.path.isfile(OUT):
        with open(OUT, 'r', encoding='utf-8') as f:
            actual = f.read().strip()
    else:
        raise AssertionError("Resolver produced neither a result on stdout nor the required output file")
    assert actual == expected, f"Expected dynamic result '{expected}', got '{actual}'"


def main():
    # Preserve the original verifier's assertion against the supplied fixtures.
    assert_original_output()

    source_stat = os.lstat(SOURCE)
    assert stat.S_ISREG(source_stat.st_mode), "resolve.c must be a regular source file"
    if os.path.exists(RUN_SH):
        assert stat.S_ISREG(os.lstat(RUN_SH).st_mode), "run.sh must be a regular file"

    binary = os.path.join(tempfile.gettempdir(), "resolve-verifier-" + secrets.token_hex(8))
    compile_proc = subprocess.run(
        ["gcc", "-std=c11", "-Wall", "-Wextra", SOURCE, "-o", binary],
        cwd=WORK, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert compile_proc.returncode == 0, (
        f"resolve.c did not compile:\n{compile_proc.stdout}\n{compile_proc.stderr}"
    )

    cases = [
        (["1.2.0", "1.10.0", "1.11.0", "0.99.9", "2.0.0"],
         [(">=", "1.2.0"), ("<", "2.0.0"), ("!=", "1.11.0")]),
        (["2.9.10", "2.10.3", "2.12.9", "3.0.0", "1.20.0"],
         [(">", "2.9.10"), ("<=", "2.12.9"), ("!=", "2.12.9")]),
        (["4.8.11", "4.8.2", "4.10.0", "5.0.0"], [("==", "4.8.11")]),
        (["7.1.0", "7.10.0", "8.0.0"], [(">", "9.0.0")]),
    ]

    rng = random.SystemRandom()
    versions = {f"{rng.randrange(0, 15)}.{rng.randrange(0, 25)}.{rng.randrange(0, 30)}" for _ in range(40)}
    while len(versions) < 24:
        versions.add(f"{rng.randrange(0, 15)}.{rng.randrange(0, 25)}.{rng.randrange(0, 30)}")
    ordered = sorted(versions, key=parse_semver)
    low = ordered[len(ordered) // 4]
    high = ordered[(3 * len(ordered)) // 4]
    excluded = ordered[len(ordered) // 2]
    shuffled = list(ordered)
    rng.shuffle(shuffled)
    cases.append((shuffled, [(">=", low), ("<=", high), ("!=", excluded)]))

    backups = {}
    for path in (AVAIL, CONST, OUT):
        backups[path] = open(path, 'rb').read() if os.path.exists(path) else None

    try:
        if os.path.exists(RUN_SH):
            # The C implementation must itself perform semantic comparison; a wrapper
            # may only supply the required transcoding/invocation layer.
            for available, constraints in cases:
                write_case(available, constraints, utf16=False)
                run_and_check([binary, AVAIL, CONST], expected_result(available, constraints), False)

            # Exercise the complete wrapper setup on fresh UTF-16LE Windows-style data.
            for available, constraints in cases:
                write_case(available, constraints, utf16=True)
                run_and_check(["bash", RUN_SH, AVAIL, CONST], expected_result(available, constraints), True)
        else:
            # Without a wrapper, the compiled C artifact must consume UTF-16LE itself.
            for available, constraints in cases:
                write_case(available, constraints, utf16=True)
                run_and_check([binary, AVAIL, CONST], expected_result(available, constraints), False)
    finally:
        for path, data in backups.items():
            if data is None:
                if os.path.exists(path):
                    os.unlink(path)
            else:
                with open(path, 'wb') as f:
                    f.write(data)
        if os.path.exists(binary):
            os.unlink(binary)


if __name__ == "__main__":
    main()
PY_EOF

if python3 -I /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
