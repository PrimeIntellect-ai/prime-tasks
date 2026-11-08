#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import importlib.util
import os
import random
import re
import shlex
import stat
import subprocess
import sys
import tempfile
import pytest


def test_phase1_auth_token():
    token_path = "/home/user/auth_token.txt"
    assert os.path.exists(token_path), f"Missing auth token file at {token_path}"

    with open(token_path, "r") as f:
        content = f.read().strip()

    expected_token = "AUTH_TOKEN: 9F8A-7B6C-5D4E-3F2A"
    assert content == expected_token, f"Token mismatch. Expected '{expected_token}', got '{content}'"


def _run_build(build_script):
    result = subprocess.run([build_script], capture_output=True, text=True, cwd="/home/user")
    assert result.returncode == 0, (
        f"Build script failed with return code {result.returncode}\n"
        f"STDOUT: {result.stdout}\nSTDERR: {result.stderr}"
    )


def _readelf_sections(path):
    result = subprocess.run(["readelf", "-S", path], capture_output=True, text=True)
    assert result.returncode == 0, f"readelf failed for {path}: {result.stderr}"
    return result.stdout


def _assert_evaluate(path):
    try:
        library = ctypes.CDLL(path)
        evaluate = library.evaluate
        evaluate.argtypes = []
        evaluate.restype = ctypes.c_double
        value = evaluate()
    except Exception as exc:
        pytest.fail(f"{path} does not export a callable C function named evaluate: {exc}")
    assert value == 0.0, f"evaluate() from {path} returned {value}, expected 0.0"


def _install_gpp_logger(log_path):
    gpp = "/usr/bin/g++"
    assert os.path.lexists(gpp), "g++ is missing"

    was_link = os.path.islink(gpp)
    link_target = os.readlink(gpp) if was_link else None
    original_mode = stat.S_IMODE(os.stat(gpp).st_mode)
    real_compiler = os.path.realpath(gpp)
    backup = None

    if was_link:
        os.unlink(gpp)
    else:
        backup = gpp + ".verifier-original"
        if os.path.lexists(backup):
            os.unlink(backup)
        os.rename(gpp, backup)
        real_compiler = backup

    wrapper = """#!/bin/sh
printf '\036' >> {log}
printf '%s\037' "$@" >> {log}
exec {compiler} "$@"
""".format(log=shlex.quote(log_path), compiler=shlex.quote(real_compiler))
    with open(gpp, "w") as f:
        f.write(wrapper)
    os.chmod(gpp, 0o755)

    def restore():
        if os.path.lexists(gpp):
            os.unlink(gpp)
        if was_link:
            os.symlink(link_target, gpp)
        else:
            os.rename(backup, gpp)
            os.chmod(gpp, original_mode)

    return restore


def _logged_calls(log_path):
    if not os.path.exists(log_path):
        return []
    with open(log_path, "rb") as f:
        data = f.read()
    calls = []
    for record in data.split(b"\x1e"):
        if not record:
            continue
        args = [part.decode("utf-8", "surrogateescape") for part in record.split(b"\x1f") if part]
        calls.append(args)
    return calls


def _output_of(args):
    for index, arg in enumerate(args):
        if arg == "-o" and index + 1 < len(args):
            return os.path.abspath(os.path.join("/home/user", args[index + 1]))
        if arg.startswith("-o") and len(arg) > 2:
            return os.path.abspath(os.path.join("/home/user", arg[2:]))
    return None


def _uses_source(args):
    for arg in args:
        if arg.startswith("-"):
            continue
        if os.path.abspath(os.path.join("/home/user", arg)) == "/home/user/calc_engine.cpp":
            return True
    return False


def _effective_optimization(args):
    options = [arg for arg in args if re.fullmatch(r"-O(?:0|1|2|3|g|s|fast)", arg)]
    return options[-1] if options else None


def test_phase2_build_script():
    build_script = "/home/user/build.sh"
    source_path = "/home/user/calc_engine.cpp"
    debug_so = "/home/user/libcalc_debug.so"
    release_so = "/home/user/libcalc_release.so"

    assert os.path.exists(build_script), f"Missing build script at {build_script}"
    assert os.access(build_script, os.X_OK), f"Build script at {build_script} is not executable"
    assert os.path.isfile(source_path), f"Missing C++ source at {source_path}"

    with open(source_path, "r") as f:
        original_source = f.read()
    assert re.search(r'extern\s+"C"\s+double\s+evaluate\s*\(', original_source), (
        "calc_engine.cpp must define extern \"C\" double evaluate()"
    )

    for output in (debug_so, release_so):
        if os.path.lexists(output):
            os.unlink(output)

    log_path = "/tmp/verifier-gpp-calls.bin"
    if os.path.exists(log_path):
        os.unlink(log_path)
    restore_gpp = _install_gpp_logger(log_path)

    instrumented_source = r'''#if defined(DEBUG_TRACE) && !defined(PRODUCTION_MODE)
# if DEBUG_TRACE != 1
#  error DEBUG_TRACE must equal 1
# endif
# ifdef __OPTIMIZE__
#  error debug build must disable optimization
# endif
#elif defined(PRODUCTION_MODE) && !defined(DEBUG_TRACE)
# if PRODUCTION_MODE != 1
#  error PRODUCTION_MODE must equal 1
# endif
# ifndef __OPTIMIZE__
#  error release build must enable optimization
# endif
#else
# error exactly one required build macro must be defined
#endif
extern "C" double evaluate() { return 0.0; }
'''

    try:
        # First build the agent's actual source and retain the original checks.
        _run_build(build_script)
        assert os.path.exists(debug_so), f"Missing debug shared library at {debug_so}"
        assert os.path.exists(release_so), f"Missing release shared library at {release_so}"

        debug_sections = _readelf_sections(debug_so)
        release_sections = _readelf_sections(release_so)
        assert ".debug_info" in debug_sections, f"Debug symbols missing in {debug_so}"
        assert ".debug_info" not in release_sections, f"Debug symbols inappropriately present in {release_so}"
        assert ".symtab" not in release_sections, f"Release library {release_so} was not stripped"
        _assert_evaluate(debug_so)
        _assert_evaluate(release_so)

        # Rebuild a probe source so the required macro values and optimization modes
        # must actually be used by each compilation, rather than merely mentioned.
        with open(source_path, "w") as f:
            f.write(instrumented_source)
        for output in (debug_so, release_so):
            os.unlink(output)
        _run_build(build_script)

        assert os.path.exists(debug_so), f"Probe build did not produce {debug_so}"
        assert os.path.exists(release_so), f"Probe build did not produce {release_so}"
        assert ".debug_info" in _readelf_sections(debug_so), f"Debug symbols missing in {debug_so}"
        release_sections = _readelf_sections(release_so)
        assert ".debug_info" not in release_sections, f"Debug symbols inappropriately present in {release_so}"
        assert ".symtab" not in release_sections, f"Release library {release_so} was not stripped"
        _assert_evaluate(debug_so)
        _assert_evaluate(release_so)
    finally:
        with open(source_path, "w") as f:
            f.write(original_source)
        restore_gpp()

    calls = _logged_calls(log_path)
    debug_calls = [args for args in calls if _output_of(args) == debug_so and _uses_source(args)]
    release_calls = [args for args in calls if _output_of(args) == release_so and _uses_source(args)]
    assert debug_calls, "build.sh did not invoke g++ on calc_engine.cpp to create libcalc_debug.so"
    assert release_calls, "build.sh did not invoke g++ on calc_engine.cpp to create libcalc_release.so"

    assert any(
        "-shared" in args and "-g" in args and "-DDEBUG_TRACE=1" in args
        and _effective_optimization(args) == "-O0"
        for args in debug_calls
    ), "Debug compilation must use -shared, -g, -O0, and -DDEBUG_TRACE=1"
    assert any(
        "-shared" in args and "-DPRODUCTION_MODE=1" in args
        and _effective_optimization(args) == "-O3"
        for args in release_calls
    ), "Release compilation must use -shared, -O3, and -DPRODUCTION_MODE=1"


def _load_sanitizer():
    sanitizer_path = "/home/user/sanitizer.py"
    assert os.path.exists(sanitizer_path), f"Missing sanitizer module at {sanitizer_path}"
    spec = importlib.util.spec_from_file_location("sanitizer", sanitizer_path)
    sanitizer = importlib.util.module_from_spec(spec)
    sys.modules["sanitizer"] = sanitizer
    try:
        spec.loader.exec_module(sanitizer)
    except Exception as exc:
        pytest.fail(f"Failed to load sanitizer.py: {exc}")
    assert hasattr(sanitizer, "is_safe_expression"), "is_safe_expression function missing in sanitizer.py"
    assert callable(sanitizer.is_safe_expression), "is_safe_expression is not callable"
    return sanitizer


def test_phase3_sanitizer_corpus():
    sanitizer = _load_sanitizer()
    clean_corpus_path = "/app/corpus/clean"
    evil_corpus_path = "/app/corpus/evil"

    assert os.path.exists(clean_corpus_path), f"Clean corpus missing at {clean_corpus_path}"
    assert os.path.exists(evil_corpus_path), f"Evil corpus missing at {evil_corpus_path}"

    clean_files = [f for f in os.listdir(clean_corpus_path) if os.path.isfile(os.path.join(clean_corpus_path, f))]
    evil_files = [f for f in os.listdir(evil_corpus_path) if os.path.isfile(os.path.join(evil_corpus_path, f))]
    clean_failures = []
    evil_failures = []

    for filename in clean_files:
        with open(os.path.join(clean_corpus_path, filename), "r") as f:
            expr = f.read().strip()
        try:
            if not sanitizer.is_safe_expression(expr):
                clean_failures.append(filename)
        except Exception:
            clean_failures.append(filename)

    for filename in evil_files:
        with open(os.path.join(evil_corpus_path, filename), "r") as f:
            expr = f.read().strip()
        try:
            if sanitizer.is_safe_expression(expr):
                evil_failures.append(filename)
        except Exception:
            pass

    errors = []
    if clean_failures:
        errors.append(f"{len(clean_failures)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failures)}")
    if evil_failures:
        errors.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed: {', '.join(evil_failures)}")
    if errors:
        pytest.fail(" | ".join(errors))


def test_phase3_sanitizer_generated_cases():
    sanitizer = _load_sanitizer()
    rng = random.SystemRandom()
    safe_cases = []
    evil_cases = []

    # Fresh arithmetic and allowed exponentiation cases.
    for _ in range(30):
        a, b, c = (rng.randint(0, 9999) for _ in range(3))
        depth = rng.randint(0, 5)
        expression = f"{a}+{b}*{c}"
        safe_cases.append("(" * depth + expression + ")" * depth)
        base = rng.randint(0, 9999)
        exponent = rng.randint(0, 9999)
        safe_cases.append(f"{base} ^ {exponent}")

    # Five levels and length 255 are boundary-safe.
    safe_cases.append("(((((7+8)))))")
    safe_cases.append("1" + "+1" * 127)  # exactly 255 characters

    # Generate each specified malicious class with values unknown before verification.
    for _ in range(20):
        depth = rng.randint(6, 12)
        evil_cases.append("(" * depth + str(rng.randint(0, 99)) + ")" * depth)

        keyword = rng.choice(["eval", "exec", "import", "system"])
        keyword = "".join(ch.upper() if rng.choice([True, False]) else ch for ch in keyword)
        evil_cases.append(f"12+{keyword}(3)")

        large = str(rng.randint(10000, 999999999))
        small = str(rng.randint(0, 9999))
        evil_cases.append(f"{large} ^ {small}")
        evil_cases.append(f"{small}^{large}")

        target_length = rng.randint(256, 420)
        evil_cases.append("1" + "+1" * ((target_length - 1) // 2) + (" " if target_length % 2 == 0 else ""))

    failures = []
    for expr in safe_cases:
        try:
            accepted = bool(sanitizer.is_safe_expression(expr))
        except Exception as exc:
            failures.append(f"safe expression raised {type(exc).__name__}: {expr[:60]!r}")
            continue
        if not accepted:
            failures.append(f"safe expression rejected: {expr[:60]!r}")

    for expr in evil_cases:
        try:
            accepted = bool(sanitizer.is_safe_expression(expr))
        except Exception:
            accepted = False
        if accepted:
            failures.append(f"evil expression accepted: {expr[:60]!r}")

    assert not failures, "Generated sanitizer failures:\n" + "\n".join(failures[:20])
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
