#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pandas as pd
import numpy as np
from scipy.integrate import solve_ivp

def test_final_state():
    csv_path = '/home/user/training_data.csv'
    img_path = '/home/user/phase_portrait.png'

    assert os.path.isfile(csv_path), f"File not found: {csv_path}"
    assert os.path.isfile(img_path), f"File not found: {img_path}"

    # Check CSV structure
    df_agent = pd.read_csv(csv_path)
    expected_columns = ['t', 'y1', 'y2']
    assert list(df_agent.columns) == expected_columns, f"Expected columns {expected_columns}, got {list(df_agent.columns)}"
    assert len(df_agent) == 3000, f"Expected 3000 rows, got {len(df_agent)}"

    # Generate Ground Truth
    def vdp(t, y):
        return [y[1], 1000 * (1 - y[0]**2) * y[1] - y[0]]

    t_eval = np.linspace(0, 3000, 3000)
    sol_true = solve_ivp(vdp, [0, 3000], [2.0, 0.0], method='Radau', t_eval=t_eval, atol=1e-9, rtol=1e-9)

    # Check time column
    np.testing.assert_allclose(
        df_agent['t'].values, 
        t_eval, 
        err_msg="Time column 't' does not match the expected evenly spaced points from 0 to 3000."
    )

    # Compute MSE
    mse_y1 = np.mean((df_agent['y1'].values - sol_true.y[0])**2)
    mse_y2 = np.mean((df_agent['y2'].values - sol_true.y[1])**2)
    total_mse = mse_y1 + mse_y2

    assert total_mse <= 1e-4, f"Total MSE {total_mse} exceeds the threshold of 1e-4"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
