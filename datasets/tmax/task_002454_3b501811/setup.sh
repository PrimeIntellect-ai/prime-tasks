#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip jq
pip3 install --default-timeout=100 pytest pandas scipy papermill jupyter nbformat

mkdir -p /home/user
cd /home/user

# Generate base data
python3 -c "
import numpy as np
import pandas as pd
np.random.seed(0)
x = np.linspace(0, 30, 100)
# True peak at 15.5
y = 10.0 * np.exp(-0.5 * ((x - 15.5) / 2.0)**2)
pd.DataFrame({'x': x, 'y': y}).to_csv('base_data.csv', index=False)
"

# Create mcmc_template.ipynb
python3 -c "
import nbformat as nbf
nb = nbf.v4.new_notebook()

code_cell_1 = nbf.v4.new_code_cell(
    \"\"\"# Parameters
input_file = 'base_data.csv'
output_json = 'result.json'
\"\"\"
)
code_cell_1.metadata['tags'] = ['parameters']

code_cell_2 = nbf.v4.new_code_cell(
    \"\"\"import pandas as pd
import numpy as np
import json
from scipy.optimize import curve_fit

df = pd.read_csv(input_file)
def gauss(x, a, mu, sigma):
    return a * np.exp(-0.5 * ((x - mu) / sigma)**2)

# Mock MCMC by using curve_fit to find the peak
popt, _ = curve_fit(gauss, df['x'], df['y'], p0=[10, 15, 2])

res = {'estimated_mu': round(popt[1], 4)}
with open(output_json, 'w') as f:
    json.dump(res, f)
\"\"\"
)

nb['cells'] = [code_cell_1, code_cell_2]
nbf.write(nb, 'mcmc_template.ipynb')
"

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
