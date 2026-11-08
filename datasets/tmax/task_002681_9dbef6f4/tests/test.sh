#!/bin/bash
mkdir -p /logs/verifier /tmp/verifier_tools /tmp/verifier_captures
rm -f /tmp/verifier_gcc.log /tmp/build_trace.log /tmp/build_status
rm -rf /tmp/verifier_captures/*

REAL_GCC="$(readlink -f /usr/bin/gcc)"
cat > /tmp/verifier_tools/gcc <<WRAP_EOF
#!/bin/bash
real_gcc=$(printf '%q' "$REAL_GCC")
log=/tmp/verifier_gcc.log
captures=/tmp/verifier_captures
has_address=0
has_undefined=0
has_o3=0
out=""
prev=""
for arg in "\$@"; do
    if [ "\$prev" = "-o" ]; then out="\$arg"; fi
    case "\$arg" in
        *-fsanitize=*address*) has_address=1 ;;
    esac
    case "\$arg" in
        *-fsanitize=*undefined*) has_undefined=1 ;;
    esac
    [ "\$arg" = "-O3" ] && has_o3=1
    prev="\$arg"
done

"\$real_gcc" "\$@"
rc=\$?

absout="\$out"
if [ -n "\$absout" ] && [[ "\$absout" != /* ]]; then
    absout="\$PWD/\$absout"
fi
{
    printf 'COMPILE address=%s undefined=%s o3=%s out=%q args=' \
        "\$has_address" "\$has_undefined" "\$has_o3" "\$absout"
    printf '%q ' "\$@"
    printf '\n'
} >> "\$log"

if [ "\$rc" -eq 0 ] && [ "\$has_address" -eq 1 ] && \
   [ "\$has_undefined" -eq 1 ] && [ -n "\$absout" ] && [ -x "\$absout" ]; then
    realout="\${absout}.verifier-real"
    mv -f -- "\$absout" "\$realout"
    quoted_real=\$(printf '%q' "\$realout")
    cat > "\$absout" <<LAUNCH_EOF
#!/bin/bash
mkdir -p /tmp/verifier_captures
input="\$1"
if [ -f "\$input" ]; then
    n=\$(find /tmp/verifier_captures -maxdepth 1 -type f | wc -l)
    cp -- "\$input" "/tmp/verifier_captures/run_\$\$_\${n}.wav"
fi
exec \$quoted_real "\$@"
LAUNCH_EOF
    chmod +x "\$absout"
fi
exit "\$rc"
WRAP_EOF
chmod +x /tmp/verifier_tools/gcc

# Intercept both PATH-based gcc and the normal absolute /usr/bin/gcc spelling.
GCC_KIND=""
GCC_LINK=""
if [ -L /usr/bin/gcc ]; then
    GCC_KIND=link
    GCC_LINK="$(readlink /usr/bin/gcc)"
    rm -f /usr/bin/gcc
    cp /tmp/verifier_tools/gcc /usr/bin/gcc
    chmod +x /usr/bin/gcc
elif [ -e /usr/bin/gcc ]; then
    GCC_KIND=file
    mv /usr/bin/gcc /usr/bin/gcc.verifier-backup
    cp /tmp/verifier_tools/gcc /usr/bin/gcc
    chmod +x /usr/bin/gcc
fi

if [ -f /home/user/build_and_test.sh ]; then
    env PATH="/tmp/verifier_tools:$PATH" timeout 180 bash -x /home/user/build_and_test.sh \
        > /tmp/build_stdout.log 2> /tmp/build_trace.log
    echo "$?" > /tmp/build_status
else
    echo 127 > /tmp/build_status
fi

# Always restore the system compiler before running the remaining checks.
rm -f /usr/bin/gcc
if [ "$GCC_KIND" = link ]; then
    ln -s "$GCC_LINK" /usr/bin/gcc
elif [ "$GCC_KIND" = file ]; then
    mv /usr/bin/gcc.verifier-backup /usr/bin/gcc
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import stat
import struct
import subprocess
from pathlib import Path

import numpy as np
import pytest
import scipy.io.wavfile as wav

SCRIPT = Path('/home/user/build_and_test.sh')
SOURCE = Path('/home/user/src/audio_filter.c')
RELEASE = Path('/home/user/audio_filter_release')
FILTERED = Path('/home/user/filtered.wav')


def test_build_and_test_script_exists_and_executable():
    path = str(SCRIPT)
    assert os.path.isfile(path), f"Missing script: {path}"
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script is not executable: {path}"


def test_build_script_executed_successfully():
    status = Path('/tmp/build_status').read_text().strip()
    trace = Path('/tmp/build_trace.log').read_text(errors='replace')
    assert status == '0', f'build_and_test.sh failed with status {status}\n{trace[-4000:]}'
    assert not any(line.lstrip('+ ').startswith(('make ', 'cmake ')) for line in trace.splitlines()), \
        'External build tools Make/CMake must not be used'


def test_pipeline_compiled_required_targets():
    log_path = Path('/tmp/verifier_gcc.log')
    assert log_path.is_file(), 'build_and_test.sh did not invoke gcc'
    lines = log_path.read_text(errors='replace').splitlines()

    sanitizer_builds = [line for line in lines
                        if 'address=1' in line and 'undefined=1' in line]
    assert sanitizer_builds, 'No gcc build enabled both AddressSanitizer and UndefinedBehaviorSanitizer'
    assert any('audio_filter.c' in line for line in sanitizer_builds), \
        'The sanitizer build did not compile audio_filter.c'

    release_builds = [line for line in lines
                      if 'o3=1' in line and 'out=/home/user/audio_filter_release' in line]
    assert release_builds, 'No -O3 gcc build produced /home/user/audio_filter_release'
    assert any('audio_filter.c' in line for line in release_builds), \
        'The release build did not compile audio_filter.c'


def test_pipeline_ran_five_varied_random_sanitizer_cases():
    captures = sorted(Path('/tmp/verifier_captures').glob('*.wav'))
    valid = []
    for path in captures:
        blob = path.read_bytes()
        if len(blob) < 44 or blob[:4] != b'RIFF' or blob[8:12] != b'WAVE':
            continue
        data_size = struct.unpack_from('<I', blob, 40)[0]
        if data_size <= len(blob) - 44:
            valid.append((data_size, hashlib.sha256(blob[44:44 + data_size]).digest()))

    assert len(valid) >= 5, \
        f'The sanitizer executable was run on only {len(valid)} valid WAV inputs; at least 5 are required'
    assert len({digest for _, digest in valid}) >= 5, \
        'The property tests did not use at least 5 distinct data payloads'
    assert len({size for size, _ in valid}) >= 2, \
        'The property-test inputs did not vary in size'


def test_release_executable_exists():
    path = str(RELEASE)
    assert os.path.isfile(path), f"Missing release executable: {path}"
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Release binary is not executable: {path}"
    assert RELEASE.read_bytes()[:4] == b'\x7fELF', 'Release artifact is not an ELF executable'


def test_filtered_wav_exists():
    path = str(FILTERED)
    assert os.path.isfile(path), f"Missing output file: {path}"


def test_filtered_wav_accuracy():
    input_path = "/app/test_speech.wav"
    output_path = str(FILTERED)

    assert os.path.isfile(input_path), f"Missing input file: {input_path}"
    assert os.path.isfile(output_path), f"Missing output file: {output_path}"

    try:
        rate1, data1 = wav.read(input_path)
    except Exception as e:
        pytest.fail(f"Failed to read input wav: {e}")

    try:
        rate2, data2 = wav.read(output_path)
    except Exception as e:
        pytest.fail(f"Failed to read output wav: {e}")

    assert rate1 == rate2, f"Sample rate mismatch: {rate1} != {rate2}"
    assert len(data1) == len(data2), f"Length mismatch: {len(data1)} != {len(data2)}"

    data_padded = np.pad(data1, (2, 0), mode='constant')
    golden = (data_padded[:-2]/3.0 + data_padded[1:-1]/3.0 + data_padded[2:]/3.0).astype(np.int16)
    mse = np.mean((data2.astype(np.float32) - golden.astype(np.float32))**2)
    assert mse < 0.01, f"MSE too high: {mse} >= 0.01. Output audio does not match the 3-tap moving average filter."


def trunc_div3(value):
    return value // 3 if value >= 0 else -((-value) // 3)


def make_wav(samples):
    payload = struct.pack('<' + 'h' * len(samples), *samples) if samples else b''
    data_size = len(payload)
    header = struct.pack(
        '<4sI4s4sIHHIIHH4sI',
        b'RIFF', 36 + data_size, b'WAVE', b'fmt ', 16, 1, 1,
        22050, 22050 * 2, 2, 16, b'data', data_size
    )
    return header + payload


def expected_samples(samples):
    result = []
    for i, sample in enumerate(samples):
        total = sample
        if i >= 1:
            total += samples[i - 1]
        if i >= 2:
            total += samples[i - 2]
        result.append(trunc_div3(total))
    return result


def assert_filter(binary, samples, case_name):
    work = Path('/tmp/verifier_behavior')
    work.mkdir(exist_ok=True)
    inp = work / f'{case_name}.wav'
    out = work / f'{case_name}.out.wav'
    original = make_wav(samples)
    inp.write_bytes(original)
    if out.exists():
        out.unlink()

    env = os.environ.copy()
    env['ASAN_OPTIONS'] = 'detect_leaks=1:halt_on_error=1'
    env['UBSAN_OPTIONS'] = 'halt_on_error=1:print_stacktrace=1'
    proc = subprocess.run([str(binary), str(inp), str(out)], stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, env=env, timeout=20)
    assert proc.returncode == 0, \
        f'{binary} failed case {case_name}:\n{proc.stderr.decode(errors="replace")}'
    produced = out.read_bytes()
    assert len(produced) == len(original), 'Output WAV length changed'
    assert produced[:44] == original[:44], 'Output WAV header/format changed'
    actual = list(struct.unpack('<' + 'h' * len(samples), produced[44:])) if samples else []
    assert actual == expected_samples(samples), \
        f'Incorrect filter output for {case_name}: {actual} != {expected_samples(samples)}'


def test_repaired_source_and_release_on_additional_inputs():
    assert SOURCE.is_file(), f'Missing source file: {SOURCE}'
    sanitized = Path('/tmp/audio_filter_verifier_sanitized')
    compile_proc = subprocess.run([
        '/usr/bin/gcc', '-O1', '-g', '-Wall', '-Wextra',
        '-fsanitize=address,undefined', '-fno-omit-frame-pointer',
        str(SOURCE), '-o', str(sanitized)
    ], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
    assert compile_proc.returncode == 0, compile_proc.stderr.decode(errors='replace')

    lengths = [1, 2, 3, 7, 31, 128, 509]
    cases = []
    for index, length in enumerate(lengths):
        raw = secrets.token_bytes(length * 2)
        samples = list(struct.unpack('<' + 'h' * length, raw))
        if index == 0:
            samples[0] = -32768
        elif index == 1:
            samples[:] = [32767, 32767]
        cases.append(samples)

    for index, samples in enumerate(cases):
        assert_filter(sanitized, samples, f'san_{index}_{secrets.token_hex(4)}')
        assert_filter(RELEASE, samples, f'rel_{index}_{secrets.token_hex(4)}')
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
