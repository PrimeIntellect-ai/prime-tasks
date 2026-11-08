#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest jupyter nbconvert numpy pandas scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/data.csv
day,infected
0,1
1,1
2,2
3,2
4,3
5,4
6,6
7,8
8,11
9,15
10,20
11,26
12,35
13,46
14,61
15,79
16,101
17,128
18,159
19,194
20,230
21,266
22,298
23,322
24,335
25,335
26,323
27,301
28,272
29,240
EOF

    cat << 'EOF' > /home/user/analysis.ipynb
{
 "cells": [
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "import numpy as np\n",
    "import pandas as pd\n",
    "from scipy.integrate import odeint\n",
    "from scipy.optimize import curve_fit\n",
    "\n",
    "def sir_deriv(y, t, N, beta, gamma):\n",
    "    S, I, R = y\n",
    "    # BUG HERE: dSdt should be negative!\n",
    "    dSdt = beta * S * I / N\n",
    "    dIdt = beta * S * I / N - gamma * I\n",
    "    dRdt = gamma * I\n",
    "    return dSdt, dIdt, dRdt\n",
    "\n",
    "def solve_sir(t, beta, gamma):\n",
    "    N = 1000\n",
    "    I0, R0 = 1, 0\n",
    "    S0 = N - I0 - R0\n",
    "    y0 = S0, I0, R0\n",
    "    ret = odeint(sir_deriv, y0, t, args=(N, beta, gamma))\n",
    "    S, I, R = ret.T\n",
    "    return I\n",
    "\n",
    "if __name__ == '__main__':\n",
    "    data = pd.read_csv('data.csv')\n",
    "    t = data['day'].values\n",
    "    I_data = data['infected'].values\n",
    "    \n",
    "    # Fit the model\n",
    "    popt, pcov = curve_fit(solve_sir, t, I_data, p0=[0.5, 0.2], bounds=(0, [2.0, 1.0]))\n",
    "    beta_fit, gamma_fit = popt\n",
    "    \n",
    "    with open('fitted_params.csv', 'w') as f:\n",
    "        f.write(f\"{beta_fit:.4f},{gamma_fit:.4f}\\n\")\n"
   ]
  }
 ],
 "metadata": {
  "kernelspec": {
   "display_name": "Python 3",
   "language": "python",
   "name": "python3"
  }
 },
 "nbformat": 4,
 "nbformat_minor": 4
}
EOF

    cat << 'EOF' > /home/user/test_regression.py
import os
import pytest

def test_fitted_parameters():
    assert os.path.exists('/home/user/fitted_params.csv'), "Fitted parameters file not found!"
    with open('/home/user/fitted_params.csv', 'r') as f:
        content = f.read().strip()

    parts = content.split(',')
    assert len(parts) == 2, "File must contain two comma-separated values."

    beta, gamma = float(parts[0]), float(parts[1])

    # Ground truth values for this specific dataset are approx beta=0.40, gamma=0.10
    assert 0.38 < beta < 0.42, f"Beta value {beta} is out of expected regression bounds!"
    assert 0.08 < gamma < 0.12, f"Gamma value {gamma} is out of expected regression bounds!"
EOF

    chmod -R 777 /home/user
