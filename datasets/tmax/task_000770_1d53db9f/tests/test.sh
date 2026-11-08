#!/bin/bash
set +e
mkdir -p /logs/verifier
printf '0\n' > /logs/verifier/reward.txt

status=0
backup_dir=$(mktemp -d /tmp/analysis-verifier.XXXXXX) || status=1
original_output="$backup_dir/original_top_candidates.csv"

cleanup() {
    if [ -f "$backup_dir/traffic.csv" ]; then
        cp -p "$backup_dir/traffic.csv" /app/data/traffic.csv 2>/dev/null || true
    fi
    if [ -f "$backup_dir/prior_specs.png" ]; then
        cp -p "$backup_dir/prior_specs.png" /app/prior_specs.png 2>/dev/null || true
    fi
    if [ -f "$original_output" ]; then
        cp "$original_output" /home/user/top_candidates.csv 2>/dev/null || true
        chown user:user /home/user/top_candidates.csv 2>/dev/null || true
    fi
    rm -rf "$backup_dir"
}
trap cleanup EXIT

if [ "$status" -eq 0 ]; then
    cp -p /app/data/traffic.csv "$backup_dir/traffic.csv" || status=1
    cp -p /app/prior_specs.png "$backup_dir/prior_specs.png" || status=1
fi

# The requested deliverable must be an actual Bash script that can regenerate
# the output rather than merely a precomputed CSV.
if [ ! -f /home/user/run_analysis.sh ]; then
    echo "Missing /home/user/run_analysis.sh"
    status=1
fi

if [ "$status" -eq 0 ]; then
    rm -f /home/user/top_candidates.csv
    timeout 90s runuser -u user -- env HOME=/home/user /bin/bash /home/user/run_analysis.sh || status=1
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest
import pandas as pd
import numpy as np

def test_final_output_mse():
    """
    Test that the output CSV exists and matches the golden implementation
    with an MSE <= 0.0001.
    """
    output_path = '/home/user/top_candidates.csv'
    dataset_path = '/app/data/traffic.csv'

    assert os.path.exists(output_path), f"Output file not found at {output_path}"
    assert os.path.exists(dataset_path), f"Dataset not found at {dataset_path}"

    # Generate Golden Implementation
    df = pd.read_csv(dataset_path)

    # Impute missing values
    df['impressions'] = df['impressions'].fillna(100).astype(float)
    df['clicks'] = df['clicks'].fillna(0).astype(float)

    # Compute Posterior CTR
    alpha = 12.0
    beta = 45.0
    df['posterior_ctr'] = (df['clicks'] + alpha) / (df['impressions'] + alpha + beta)

    # Compute Cosine Similarity to [1, 0, 0]
    df['similarity'] = df['emb_x']

    # Filter and Sort
    df_filtered = df[df['similarity'] >= 0.82].copy()
    df_sorted = df_filtered.sort_values(by=['posterior_ctr', 'id'], ascending=[False, True])
    golden_top = df_sorted.head(50)[['id', 'posterior_ctr', 'similarity']].reset_index(drop=True)

    # Load Agent's Output
    try:
        agent_df = pd.read_csv(output_path)
    except Exception as e:
        pytest.fail(f"Failed to read agent's CSV output: {e}")

    assert len(agent_df) == 50, f"Expected exactly 50 rows in the output, got {len(agent_df)}"

    # Required columns
    expected_cols = ['id', 'posterior_ctr', 'similarity']
    for col in expected_cols:
        assert col in agent_df.columns, f"Missing required column '{col}' in output CSV."

    # Calculate MSE
    mse_ctr = np.mean((golden_top['posterior_ctr'] - agent_df['posterior_ctr'])**2)
    mse_sim = np.mean((golden_top['similarity'] - agent_df['similarity'])**2)

    id_matches = (golden_top['id'].values == agent_df['id'].values).sum()
    penalty = (50 - id_matches) * 1.0

    total_mse = mse_ctr + mse_sim + penalty

    threshold = 0.0001
    assert total_mse <= threshold, (
        f"Total MSE is too high. Expected <= {threshold}, got {total_mse}. "
        f"Breakdown: CTR MSE={mse_ctr}, Similarity MSE={mse_sim}, ID Penalty={penalty}"
    )
TEST_EOF

if [ "$status" -eq 0 ]; then
    python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 || status=1
fi

# Preserve the correctly regenerated original result while testing the script
# against a second, unpredictable dataset and OCR note.
if [ "$status" -eq 0 ]; then
    cp /home/user/top_candidates.csv "$original_output" || status=1
fi

if [ "$status" -eq 0 ]; then
python3 << 'PY' || status=1
import csv
import math
import os
import random
import secrets
from PIL import Image, ImageDraw, ImageFont

rng = random.Random(secrets.randbits(128))
alpha = rng.randint(5, 19)
beta = rng.randint(25, 60)
threshold = rng.choice([0.35, 0.42, 0.50, 0.55])

font = ImageFont.truetype(
    '/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf', 28
)
img = Image.new('RGB', (760, 300), 'white')
draw = ImageDraw.Draw(img)
text = (
    'Bayesian Prior specs:\n'
    f'Alpha: {alpha}\n'
    f'Beta: {beta}\n\n'
    'Target Embedding Threshold:\n'
    f'Similarity_Threshold: {threshold:.2f}'
)
draw.text((20, 15), text, fill='black', font=font, spacing=7)
img.save('/app/prior_specs.png')
os.chmod('/app/prior_specs.png', 0o644)

rows = []
for i in range(1, 401):
    # Guarantee ample qualifying rows while retaining varied normalized vectors.
    if i <= 120:
        x = 0.60 + (i % 90) * 0.003
        angle = rng.uniform(0.0, 2.0 * math.pi)
        yz = math.sqrt(1.0 - x * x)
        y, z = yz * math.cos(angle), yz * math.sin(angle)
    else:
        x, y, z = (rng.uniform(-1.0, 1.0) for _ in range(3))
        norm = math.sqrt(x*x + y*y + z*z)
        x, y, z = x/norm, y/norm, z/norm

    imp_num = rng.randint(50, 500)
    click_num = rng.randint(0, imp_num)
    impressions = '' if i % 17 == 0 else str(imp_num)
    clicks = '' if i % 19 == 0 else str(click_num)
    rows.append([i, clicks, impressions, f'{x:.6f}', f'{y:.6f}', f'{z:.6f}'])

with open('/app/data/traffic.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['id', 'clicks', 'impressions', 'emb_x', 'emb_y', 'emb_z'])
    writer.writerows(rows)
os.chmod('/app/data/traffic.csv', 0o644)

expected = []
for ad_id, clicks, impressions, sx, sy, sz in rows:
    c = 0.0 if clicks == '' else float(clicks)
    imp = 100.0 if impressions == '' else float(impressions)
    x, y, z = float(sx), float(sy), float(sz)
    similarity = x / math.sqrt(x*x + y*y + z*z)
    posterior = (c + alpha) / (imp + alpha + beta)
    if similarity >= threshold:
        expected.append((ad_id, posterior, similarity))
expected.sort(key=lambda row: (-row[1], row[0]))
expected = expected[:50]
assert len(expected) == 50

with open('/tmp/golden_challenge.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['id', 'posterior_ctr', 'similarity'])
    writer.writerows(expected)
os.chmod('/tmp/golden_challenge.csv', 0o600)
PY
fi

if [ "$status" -eq 0 ]; then
    rm -f /home/user/top_candidates.csv
    timeout 90s runuser -u user -- env HOME=/home/user /bin/bash /home/user/run_analysis.sh || status=1
fi

cat << 'TEST_EOF' > /tmp/test_dynamic_pipeline.py
import os
import numpy as np
import pandas as pd


def test_script_recomputes_dynamic_ocr_pipeline():
    output_path = '/home/user/top_candidates.csv'
    assert os.path.exists(output_path), f"Output file not found at {output_path}"

    agent_df = pd.read_csv(output_path)
    golden_top = pd.read_csv('/tmp/golden_challenge.csv')

    expected_cols = ['id', 'posterior_ctr', 'similarity']
    assert list(agent_df.columns) == expected_cols, (
        f"Expected exactly columns {expected_cols}, got {list(agent_df.columns)}"
    )
    assert len(agent_df) == 50, f"Expected exactly 50 rows, got {len(agent_df)}"

    for col in expected_cols:
        assert col in agent_df.columns, f"Missing required column '{col}' in output CSV."

    mse_ctr = np.mean((golden_top['posterior_ctr'] - agent_df['posterior_ctr']) ** 2)
    mse_sim = np.mean((golden_top['similarity'] - agent_df['similarity']) ** 2)
    id_matches = (golden_top['id'].values == agent_df['id'].values).sum()
    penalty = (50 - id_matches) * 1.0
    total_mse = mse_ctr + mse_sim + penalty

    threshold = 0.0001
    assert total_mse <= threshold, (
        f"Dynamic pipeline result is incorrect: total MSE {total_mse} exceeds {threshold}. "
        f"Breakdown: CTR MSE={mse_ctr}, Similarity MSE={mse_sim}, ID Penalty={penalty}"
    )
TEST_EOF

if [ "$status" -eq 0 ]; then
    python3 -m pytest /tmp/test_dynamic_pipeline.py -x --tb=short 2>&1 || status=1
fi

if [ "$status" -eq 0 ]; then
    printf '1\n' > /logs/verifier/reward.txt
else
    printf '0\n' > /logs/verifier/reward.txt
fi

exit 0
