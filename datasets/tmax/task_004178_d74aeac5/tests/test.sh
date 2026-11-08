#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import stat
import subprocess
import tempfile

EXPECTED_CONTENT = (
    "frontend main\n"
    "server backend1 10.0.0.1:45\n"
    "server backend2 10.0.0.2:20\n"
)


def run_eval(path, expression, expected):
    result = subprocess.run(
        [path, expression],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=5,
    )
    assert result.returncode == 0, (
        f"{path} failed for {expression!r}: {result.stderr}"
    )
    assert result.stdout == f"{expected}\n", (
        f"{path} produced {result.stdout!r} for {expression!r}; "
        f"expected {expected!r} followed by a newline."
    )


def test_eval_executable_exists():
    path = "/home/user/eval"
    assert os.path.isfile(path), f"The executable '{path}' was not found."
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"The file '{path}' is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"'{path}' is not a compiled ELF executable."


def test_eval_source_and_behavior():
    source = "/home/user/eval.c"
    assert os.path.isfile(source), f"The C source file '{source}' was not found."

    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "eval")
        compiled = subprocess.run(
            ["gcc", source, "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        assert compiled.returncode == 0, f"eval.c does not compile with gcc:\n{compiled.stderr}"

        a = secrets.randbelow(800) + 101
        b = secrets.randbelow(90) + 2
        c = secrets.randbelow(30) + 2
        d = secrets.randbelow(100) + 1
        cases = [
            (f"{a} {b} +", a + b),
            (f"{a} {b} -", a - b),
            (f"{b} {c} *", b * c),
            (f"{a} {c} /", a // c),
            (f"{a} {b} + {c} * {d} -", (a + b) * c - d),
            (f"{a} {c} / {b} + {d} *", (a // c + b) * d),
        ]
        for executable in ("/home/user/eval", rebuilt):
            for expression, expected in cases:
                run_eval(executable, expression, expected)


def test_proxy_conf_content():
    path = "/home/user/proxy.conf"
    assert os.path.isfile(path), f"The configuration file '{path}' was not found."

    with open(path, 'r') as f:
        actual_content = f.read()

    assert actual_content.strip() == EXPECTED_CONTENT.strip(), (
        f"The contents of '{path}' do not match the expected output.\n"
        f"Expected:\n{EXPECTED_CONTENT}\n"
        f"Actual:\n{actual_content}"
    )


def test_test_sh_not_bypassed():
    path = "/home/user/test.sh"
    assert os.path.isfile(path), f"The script '{path}' was not found."

    with open(path, 'r') as f:
        content = f.read()

    assert "backend1" in content, f"'{path}' appears to be bypassed or missing 'backend1' logic."
    assert "backend2" in content, f"'{path}' appears to be bypassed or missing 'backend2' logic."
    assert "&" in content, f"'{path}' must retain the concurrency (backgrounding '&') logic."


def test_script_executes_evaluations_concurrently_and_orders_output():
    eval_path = "/home/user/eval"
    token = secrets.token_hex(8)
    base = f"/tmp/verifier-{token}"
    marker1 = base + ".backend1"
    marker2 = base + ".backend2"
    call_log = base + ".calls"
    backup = base + ".real-eval"
    value1 = secrets.randbelow(8000) + 1000
    value2 = secrets.randbelow(8000) + 1000

    wrapper = f'''#!/bin/bash
set -u
case "$1" in
  "10 5 + 3 *")
    kind=backend1
    value={value1}
    marker={marker1!r}
    ;;
  "100 10 / 2 *")
    kind=backend2
    value={value2}
    marker={marker2!r}
    ;;
  *)
    exit 90
    ;;
esac
printf '%s\n' "$1" >> {call_log!r}
touch "$marker"
# Both evaluator calls must be alive before either can complete. A sequential
# implementation therefore times out instead of passing this rendezvous.
for i in $(seq 1 100); do
  if [ -e {marker1!r} ] && [ -e {marker2!r} ]; then
    break
  fi
  sleep 0.05
done
if [ ! -e {marker1!r} ] || [ ! -e {marker2!r} ]; then
  exit 91
fi
# Force backend2's calculation to complete first, so the script must explicitly
# synchronize and emit the configuration in backend order.
if [ "$kind" = backend1 ]; then
  sleep 0.3
fi
printf '%s\n' "$value"
'''

    os.replace(eval_path, backup)
    try:
        with open(eval_path, "w") as f:
            f.write(wrapper)
        os.chmod(eval_path, 0o755)

        result = subprocess.run(
            ["/home/user/test.sh"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0, f"test.sh failed when executed:\n{result.stderr}"

        with open(call_log, "r") as f:
            calls = f.read().splitlines()
        assert sorted(calls) == sorted(["10 5 + 3 *", "100 10 / 2 *"]), (
            "test.sh must invoke eval exactly once for each backend expression. "
            f"Observed calls: {calls!r}"
        )

        expected = (
            "frontend main\n"
            f"server backend1 10.0.0.1:{value1}\n"
            f"server backend2 10.0.0.2:{value2}\n"
        )
        with open("/home/user/proxy.conf", "r") as f:
            actual = f.read()
        assert actual == expected, (
            "test.sh did not use the evaluator results or did not preserve backend order.\n"
            f"Expected:\n{expected}\nActual:\n{actual}"
        )
    finally:
        if os.path.lexists(eval_path):
            os.unlink(eval_path)
        os.replace(backup, eval_path)
        for path in (marker1, marker2, call_log):
            if os.path.exists(path):
                os.unlink(path)

    # Run the submitted script with the submitted evaluator and retain the
    # required final configuration. Repetition also exercises the real race.
    for _ in range(3):
        result = subprocess.run(
            ["/home/user/test.sh"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0, f"test.sh failed with the submitted eval:\n{result.stderr}"
        with open("/home/user/proxy.conf", "r") as f:
            actual = f.read()
        assert actual.strip() == EXPECTED_CONTENT.strip(), (
            "Executing test.sh did not generate the required ordered configuration.\n"
            f"Expected:\n{EXPECTED_CONTENT}\nActual:\n{actual}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
