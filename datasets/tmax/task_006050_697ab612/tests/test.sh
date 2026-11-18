#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_task.py
import math
import os
import re
import secrets
import shutil
import subprocess
import tempfile
from pathlib import Path

HOME = Path('/home/user')
SOURCE = HOME / 'mcmc_degrade.c'
SCRIPT = HOME / 'run_pipeline.sh'
OUTPUT = HOME / 'posterior_mean.txt'


def run_pipeline(env=None):
    subprocess.run(
        ['bash', str(SCRIPT)],
        cwd=str(HOME),
        env=env,
        check=True,
        timeout=120,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def read_output():
    assert OUTPUT.is_file(), f'Output file {OUTPUT} is missing. Did the pipeline run correctly?'
    raw = OUTPUT.read_text()
    assert re.fullmatch(r'-?\d+\.\d{3}\n?', raw), \
        'posterior_mean.txt must contain only one value formatted to exactly 3 decimal places.'
    return raw.strip(), raw


# Preserve the original final-state assertions.
assert SOURCE.is_file(), f'File {SOURCE} is missing.'
content = SOURCE.read_text()
assert 'double dt = 0.01;' in content, \
    "The step size 'dt' was not updated to 0.01 in mcmc_degrade.c."
assert 'double dt = 2.0;' not in content, \
    "The buggy step size 'dt = 2.0;' is still present in mcmc_degrade.c."
assert SCRIPT.is_file(), f'Script {SCRIPT} is missing.'

# Reject obvious use of another scripting-language interpreter in the pipeline.
for line in SCRIPT.read_text().splitlines():
    command = line.split('#', 1)[0]
    assert not re.search(r'(^|[;&|]\s*|\$\()\s*(python(?:3)?|perl|ruby|node)\b', command), \
        'run_pipeline.sh must be a pure Bash/standard-CLI pipeline.'

# Execute the submitted pipeline normally.
OUTPUT.unlink(missing_ok=True)
(HOME / 'mcmc_run').unlink(missing_ok=True)
run_pipeline()

# Recheck the source in case the pipeline altered it.
content = SOURCE.read_text()
assert 'double dt = 0.01;' in content
assert 'double dt = 2.0;' not in content

submitted_mean, genuine_raw = read_output()
assert submitted_mean in ['0.299', '0.300', '0.301'], \
    f"Expected posterior mean to be 0.299, 0.300, or 0.301, but got '{submitted_mean}'."

# Independently compile the submitted C source and derive the expected posterior
# mean from three complete 5500-sample chains with the required seeds.
reference_exe = Path('/tmp/verifier_mcmc_run')
subprocess.run(
    ['gcc', '-O2', 'mcmc_degrade.c', '-o', str(reference_exe), '-lm'],
    cwd=str(HOME), check=True, timeout=60,
    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
)
retained = []
for seed in (10, 20, 30):
    result = subprocess.run(
        [str(reference_exe), str(seed)], check=True, timeout=60,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    )
    lines = result.stdout.splitlines()
    assert len(lines) == 5500, f'Chain {seed} produced {len(lines)} lines instead of 5500.'
    values = [float(x) for x in lines]
    assert all(math.isfinite(x) for x in values), f'Chain {seed} contains non-finite samples.'
    retained.extend(values[500:])
assert len(retained) == 15000
expected_mean = f'{sum(retained) / len(retained):.3f}'
assert submitted_mean == expected_mean, \
    f'posterior_mean.txt is {submitted_mean}, but recomputing the required chains gives {expected_mean}.'

# Exercise orchestration with a verifier-controlled compiler/runner. The runner
# emits secret, seed-specific chains whose burn-in differs from retained data,
# so a hardcoded answer or incorrect seeds/counts/burn-in cannot pass.
probe_root = Path(tempfile.mkdtemp(prefix='pipeline_probe_'))
probe_bin = probe_root / 'bin'
probe_bin.mkdir()
compile_log = probe_root / 'compile.log'
run_log = probe_root / 'runs.log'
values_file = probe_root / 'values'
shift = secrets.randbelow(201) / 1000.0
probe_values = {
    10: 0.111123 + shift,
    20: 0.422123 + shift,
    30: 0.733123 + shift,
}
values_file.write_text(''.join(f'{seed} {value:.6f}\n' for seed, value in probe_values.items()))

fake_gcc = probe_bin / 'gcc'
fake_gcc.write_text(f'''#!/bin/bash
printf '%s\\n' "$*" >> {compile_log!s}
if [[ "$#" -ne 5 || "$1" != "-O2" || "$2" != "mcmc_degrade.c" || "$3" != "-o" || "$4" != "mcmc_run" || "$5" != "-lm" ]]; then
    exit 91
fi
cat > mcmc_run <<'RUNNER_EOF'
#!/bin/bash
if [[ "$#" -ne 1 ]]; then exit 92; fi
seed="$1"
printf '%s\\n' "$seed" >> {run_log!s}
value=$(awk -v s="$seed" '$1 == s {{ print $2 }}' {values_file!s})
[[ -n "$value" ]] || exit 93
awk -v v="$value" 'BEGIN {{ for (i=0; i<500; i++) printf "9.876543\\n"; for (i=0; i<5000; i++) printf "%.6f\\n", v }}'
RUNNER_EOF
chmod +x mcmc_run
''')
fake_gcc.chmod(0o755)

probe_env = os.environ.copy()
probe_env['PATH'] = str(probe_bin) + os.pathsep + probe_env.get('PATH', '')
try:
    OUTPUT.unlink(missing_ok=True)
    (HOME / 'mcmc_run').unlink(missing_ok=True)
    run_pipeline(probe_env)
    probe_mean, _ = read_output()
    expected_probe = f'{sum(probe_values.values()) / 3.0:.3f}'
    assert probe_mean == expected_probe, \
        f'Pipeline produced {probe_mean} on verifier-controlled chains; expected {expected_probe}.'

    assert compile_log.is_file(), 'The pipeline did not invoke gcc through PATH.'
    compile_calls = compile_log.read_text().splitlines()
    assert compile_calls == ['-O2 mcmc_degrade.c -o mcmc_run -lm'], \
        f'Expected exactly gcc -O2 mcmc_degrade.c -o mcmc_run -lm; got {compile_calls}.'

    assert run_log.is_file(), 'The compiled executable was not run.'
    calls = run_log.read_text().splitlines()
    assert sorted(calls) == ['10', '20', '30'] and len(calls) == 3, \
        f'Expected one chain each with seeds 10, 20, and 30; got {calls}.'
finally:
    OUTPUT.write_text(genuine_raw)
    shutil.rmtree(probe_root, ignore_errors=True)
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
