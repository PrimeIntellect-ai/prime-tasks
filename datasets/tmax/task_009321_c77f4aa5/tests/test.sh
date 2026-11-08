#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

def test_p_value_file():
    """Test that p_value.txt exists and contains the correct formatted p-value."""
    p_value_file = '/home/user/p_value.txt'
    input_file = '/home/user/input_data.parquet'

    assert os.path.exists(p_value_file), f"Expected file {p_value_file} does not exist."
    assert os.path.exists(input_file), f"Input file {input_file} does not exist."

    try:
        import pandas as pd
        import numpy as np
        from sklearn.preprocessing import StandardScaler
        from sklearn.decomposition import PCA
        from scipy import stats
    except ImportError as e:
        pytest.fail(f"Required library for validation is missing: {e}")

    # Compute expected p-value
    df = pd.read_parquet(input_file)
    features = [f'feat_{i}' for i in range(50)]
    X = df[features]

    X_scaled = StandardScaler().fit_transform(X)
    pca = PCA(n_components=2)
    components = pca.fit_transform(X_scaled)

    pc1 = components[:, 0]
    gX = pc1[df['category'] == 'X']
    gY = pc1[df['category'] == 'Y']

    res = stats.ttest_ind(gX, gY, equal_var=False)
    expected_p_value = f"{res.pvalue:.4f}"

    with open(p_value_file, 'r') as f:
        agent_p_value = f.read().strip()

    assert agent_p_value == expected_p_value, f"Expected p-value {expected_p_value}, got {agent_p_value}"

def test_output_parquet_file():
    """Test that output_data.parquet exists, has the right schema, and contains correct PCA values."""
    output_file = '/home/user/output_data.parquet'
    input_file = '/home/user/input_data.parquet'

    assert os.path.exists(output_file), f"Expected file {output_file} does not exist."

    try:
        import pandas as pd
        import numpy as np
        from sklearn.preprocessing import StandardScaler
        from sklearn.decomposition import PCA
    except ImportError as e:
        pytest.fail(f"Required library for validation is missing: {e}")

    out_df = pd.read_parquet(output_file)

    assert list(out_df.columns) == ['category', 'pc1', 'pc2'], "Output columns are incorrect. Expected ['category', 'pc1', 'pc2']."
    assert len(out_df) == 1000, f"Output length is incorrect. Expected 1000, got {len(out_df)}."

    # Compute expected PCA values
    df = pd.read_parquet(input_file)
    features = [f'feat_{i}' for i in range(50)]
    X = df[features]

    X_scaled = StandardScaler().fit_transform(X)
    pca = PCA(n_components=2)
    components = pca.fit_transform(X_scaled)

    expected_pc1 = components[:, 0]
    expected_pc2 = components[:, 1]

    # PCA components can have their signs flipped
    pc1_match = np.allclose(out_df['pc1'], expected_pc1, atol=1e-4) or np.allclose(out_df['pc1'], -expected_pc1, atol=1e-4)
    assert pc1_match, "PC1 values do not match the expected properly scaled PCA output."

    pc2_match = np.allclose(out_df['pc2'], expected_pc2, atol=1e-4) or np.allclose(out_df['pc2'], -expected_pc2, atol=1e-4)
    assert pc2_match, "PC2 values do not match the expected properly scaled PCA output."

    # Check that category matches input
    assert (out_df['category'] == df['category']).all(), "Category column in output does not match the input data."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
