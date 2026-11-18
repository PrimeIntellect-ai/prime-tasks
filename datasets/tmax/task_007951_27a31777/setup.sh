#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest papermill jupyter numpy scipy ipykernel

    mkdir -p /home/user
    cat << 'EOF' > /home/user/simulate.ipynb
{
 "cells": [
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {
    "tags": ["parameters"]
   },
   "outputs": [],
   "source": [
    "k = 0.01"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "import numpy as np\n",
    "from scipy.integrate import solve_ivp\n",
    "\n",
    "def system(t, z):\n",
    "    x, y = z\n",
    "    return [-k * x, -3 * k * y]\n",
    "\n",
    "sol = solve_ivp(system, [0, 5], [1.0, 1.0], t_eval=np.linspace(0, 5, 50))\n",
    "M = sol.y.T\n",
    "cond = np.linalg.cond(M)\n",
    "if cond > 20:\n",
    "    raise ValueError(f\"Matrix is near-singular, condition number {cond}\")\n",
    "U, S, V = np.linalg.svd(M)\n",
    "print(\"Success!\")"
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

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
