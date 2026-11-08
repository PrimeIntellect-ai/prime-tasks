#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

PROJECT = Path('/home/user/rust-linker-debug')
MANIFEST = Path('/home/user/clib/manifest.json')
LIBOPS = Path('/home/user/clib/libops.a')


def run(cmd, *, cwd=None, env=None, timeout=180):
    result = subprocess.run(
        cmd,
        cwd=cwd,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
    )
    assert result.returncode == 0, f"Command failed: {' '.join(map(str, cmd))}\n{result.stdout}"
    return result.stdout


def test_test_results_log_exists():
    path = '/home/user/test_results.log'
    assert os.path.isfile(path), f'File {path} does not exist. Did you run the cargo test command and redirect the output?'


def test_test_results_log_contents():
    path = '/home/user/test_results.log'
    with open(path, 'r') as f:
        content = f.read()
    assert 'test tests::test_mul_properties ... ok' in content, 'The property test `test_mul_properties` did not run successfully or was not found in the log.'


def test_build_rs_logic():
    path = PROJECT / 'build.rs'
    content = path.read_text()
    assert 'serde_json' in content, 'build.rs does not appear to use serde_json to parse the manifest.'
    assert 'semver' in content or 'Version' in content, 'build.rs does not appear to use semver for version checking.'
    assert 'cargo:rustc-cfg=use_v2' in content, "build.rs does not output the 'cargo:rustc-cfg=use_v2' flag."


def test_lib_rs_logic():
    path = PROJECT / 'src/lib.rs'
    content = path.read_text()
    assert 'use_v2' in content, "src/lib.rs does not appear to use the 'use_v2' cfg flag."
    assert 'proptest' in content, 'src/lib.rs does not appear to use the proptest macro/crate.'
    assert 'ops_mul_v2' in content, 'src/lib.rs does not declare or call ops_mul_v2.'


def strip_rust_comments(source):
    source = re.sub(r'/\*.*?\*/', '', source, flags=re.S)
    source = re.sub(r'//[^\n]*', '', source)
    return source


def proptest_block(source):
    match = re.search(r'proptest\s*!\s*\{', source)
    assert match, 'src/lib.rs must contain an active-looking proptest! macro invocation, not just the word in a comment.'
    start = source.find('{', match.start())
    depth = 0
    for pos in range(start, len(source)):
        if source[pos] == '{':
            depth += 1
        elif source[pos] == '}':
            depth -= 1
            if depth == 0:
                return source[start + 1:pos]
    raise AssertionError('Could not parse the proptest! block in src/lib.rs')


def test_real_build_behavior_and_property_test():
    source = strip_rust_comments((PROJECT / 'src/lib.rs').read_text())
    block = proptest_block(source)
    assert re.search(r'fn\s+test_mul_properties\b', block), 'test_mul_properties must be declared inside proptest!.'
    assert 'safe_mul' in block, 'The property test must exercise safe_mul.'
    assert '-1000' in source and '1000' in source, 'The property test must use the requested -1000 to 1000 bounds.'

    original_manifest = MANIFEST.read_bytes()
    original_library = LIBOPS.read_bytes()
    work = Path(tempfile.mkdtemp(prefix='rust-linker-verifier-'))
    try:
        # Execute the submitted test against the supplied v2 library in a clean
        # target directory, rather than trusting the submitted log.
        env = os.environ.copy()
        env['CARGO_TARGET_DIR'] = str(work / 'target-real')
        env['PROPTEST_CASES'] = '128'
        output = run(
            ['cargo', 'test', 'test_mul_properties', '--', '--nocapture'],
            cwd=PROJECT,
            env=env,
            timeout=300,
        )
        assert 'test tests::test_mul_properties ... ok' in output, 'The real property test did not execute successfully.'

        # Install a verifier-controlled library whose v1 and v2 entry points
        # deliberately return distinguishable values. This verifies both cfg
        # branches and that v2 is called with flags=0.
        c_path = work / 'ops_probe.c'
        o_path = work / 'ops_probe.o'
        c_path.write_text('''
int ops_mul(int a, int b) { return a * b + 12345; }
int ops_mul_v2(int a, int b, int flags) {
    return flags == 0 ? a * b : a * b - 54321;
}
''')
        run(['gcc', '-c', str(c_path), '-o', str(o_path)])
        probe_archive = work / 'libops.a'
        run(['ar', 'rcs', str(probe_archive), str(o_path)])
        shutil.copyfile(probe_archive, LIBOPS)

        runner = work / 'runner'
        (runner / 'src').mkdir(parents=True)
        (runner / 'Cargo.toml').write_text('''
[package]
name = "verifier-runner"
version = "0.1.0"
edition = "2021"

[dependencies]
rust-linker-debug = { path = "/home/user/rust-linker-debug" }
''')

        cases = [(-17, 23), (0, 999), (31, -29), (1000, 1000)]

        def exercise(version, use_v2, label):
            # Reformat and reorder the JSON so that merely scraping the original
            # manifest text cannot satisfy the build-script requirement.
            MANIFEST.write_text(json.dumps({
                'libs': '-L/home/user/clib -lops',
                'version': version,
                'name': 'libops',
                'cflags': '-I/home/user/clib/include',
            }, indent=4) + '\n')
            assertions = []
            for a, b in cases:
                expected = a * b if use_v2 else a * b + 12345
                assertions.append(
                    f'assert_eq!(rust_linker_debug::safe_mul({a}, {b}), {expected});'
                )
            (runner / 'src/main.rs').write_text('fn main() {\n' + '\n'.join(assertions) + '\n}\n')
            case_env = os.environ.copy()
            case_env['CARGO_TARGET_DIR'] = str(work / ('target-' + label))
            run(['cargo', 'run', '--quiet'], cwd=runner, env=case_env, timeout=300)

        exercise('2.1.3', True, 'v2')
        exercise('1.9.9', False, 'v1')
        exercise('10.0.0', True, 'v10')
    finally:
        MANIFEST.write_bytes(original_manifest)
        LIBOPS.write_bytes(original_library)
        shutil.rmtree(work, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
