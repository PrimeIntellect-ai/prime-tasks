#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest jupyter nbconvert numpy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/bio_sim.c
#include <omp.h>
#include <stdlib.h>
#include <stdio.h>

double compute_total_mass(double* state, int n) {
    double total_mass = 0.0;
    // TODO: Fix non-deterministic floating point reduction
    #pragma omp parallel for
    for (int i = 0; i < n; i++) {
        #pragma omp atomic
        total_mass += state[i];
    }
    return total_mass;
}

void solve_lu(double* A, double* b, int n) {
    // TODO: Implement LU decomposition and forward/backward substitution to solve Ax = b.
    // A is modified in-place to store L and U. b is modified in-place to store the solution x.

}
EOF

    cat << 'EOF' > /home/user/Makefile
all:
	gcc -shared -o libbiosim.so -fPIC -O3 -fopenmp bio_sim.c
EOF

    cat << 'EOF' > /home/user/workflow.ipynb
{
 "cells": [
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "import ctypes\n",
    "import numpy as np\n",
    "import json\n",
    "\n",
    "lib = ctypes.CDLL('./libbiosim.so')\n",
    "lib.compute_total_mass.restype = ctypes.c_double\n",
    "lib.compute_total_mass.argtypes = [np.ctypeslib.ndpointer(dtype=np.float64), ctypes.c_int]\n",
    "lib.solve_lu.restype = None\n",
    "lib.solve_lu.argtypes = [np.ctypeslib.ndpointer(dtype=np.float64), np.ctypeslib.ndpointer(dtype=np.float64), ctypes.c_int]\n",
    "\n",
    "def run_sim():\n",
    "    A = np.array([\n",
    "        [4.0, 1.0, 0.0, 0.0],\n",
    "        [1.0, 4.0, 1.0, 0.0],\n",
    "        [0.0, 1.0, 4.0, 1.0],\n",
    "        [0.0, 0.0, 1.0, 3.0]\n",
    "    ], dtype=np.float64)\n",
    "    b = np.array([1.0, 2.0, 3.0, 4.0], dtype=np.float64)\n",
    "    \n",
    "    lib.solve_lu(A, b, 4)\n",
    "    \n",
    "    state = b.copy()\n",
    "    mass = lib.compute_total_mass(state, 4)\n",
    "    return state, mass\n",
    "\n",
    "masses = []\n",
    "for _ in range(50):\n",
    "    state, mass = run_sim()\n",
    "    masses.append(mass)\n",
    "\n",
    "assert len(set(masses)) == 1, \"Masses are not reproducible!\"\n",
    "assert np.abs(masses[0]) > 0.0, \"Mass is zero, LU solver failed to produce valid output!\"\n",
    "assert np.abs(state[0] - 0.1219512195121951) < 1e-5, \"LU output is incorrect\"\n",
    "\n",
    "with open('sim_result.json', 'w') as f:\n",
    "    json.dump({\"state\": state.tolist(), \"mass\": masses[0]}, f)\n",
    "print(\"Simulation successful.\")\n"
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
