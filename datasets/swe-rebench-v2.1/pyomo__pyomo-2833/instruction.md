BARON Writer Outputs Inconsistent Constraint Expressions for Model with Fixed `Var` Objects
## Summary

<!-- Explain, in a clear and concise way, the command you ran and the result you were trying to achieve.
Example: "I ran `pyomo solve` to optimize a model and ..." -->
For fixed reals $x, t, u_0, u_1$, consider the model
```math
P(x, t, u_0, u_1):~~\begin{array}[t]{clll}
		\displaystyle \min_{d_0, d_1, z_{0}, z_{1} \geq 0}
		& \displaystyle d_0 + d_1 \\
		\mathrm{s.t.} & (x - 4)^2 + (z_{i} - 1)^2 - t \leq 0 \qquad & i = 0, 1 \quad & (\text{epigraph}) \\
		& z_{i} = d_0 + u_{i} d_{1} & i = 0, 1 \quad & (\text{DR}) \\
		& \sqrt{u}_{i}x - u_iz - 2 \leq 0 & i = 0, 1 \quad & (\text{Leyffer})
	\end{array}
```
If $x$ is represented by a fixed `Var` object in the implementation of this model, instead of, say, an immutable `Param` object, then the *.bar file obtained via the BARON writer seems to contain an incorrect representation of the "epigraph" constraints. More precisely, instead of the original epigraph constraints

```math
(x - 4)^2 + (z_{i} - 1)^2 - t \leq 0, \qquad i = 0, 1
```

the BARON writer output actually represents

```math
-(x - 4)^2 + (z_{i} - 1)^2 - t \leq 0, \qquad i = 0, 1
```

Since the Pyomo BARON solver interface (`solvers.plugins.solvers.BARON`) relies on the Pyomo BARON writer, solving the Pyomo model with BARON may yield an incorrect result. This issue may also affect the PyROS solver (`contrib.pyros`), which makes extensive use of models with fixed `Var` objects, if BARON is passed as a subsolver.

### Steps to reproduce the issue

<!-- Please include the command run and/or provide an example script that demonstrates the problem. -->
Script for building, writing, and solving the Pyomo model with $x=3.5, t = 0.55, u_0 = 9/8, u_1 = 13/10$:

```python
# example.py
import pyomo.environ as pyo


def create_model(x, t, u0, u1, make_x_fixed_var=True):
    """
    Create model.
    """
    m = pyo.ConcreteModel()

    if make_x_fixed_var:
        m.x = pyo.Var(initialize=x)
        m.x.fix()
    else:
        m.x = pyo.Param(initialize=x)

    m.u = pyo.Param(initialize=9/8)
    m.d0 = pyo.Var(bounds=(0, None))
    m.d1 = pyo.Var(bounds=(0, None))

    m.scenarios = pyo.Block(range(2))
    for u_val, blk in zip([u0, u1], m.scenarios.values()):
        blk.z = pyo.Var(bounds=(0, None))
        blk.u = pyo.Param(initialize=u_val)

        blk.epigraph_con = pyo.Constraint(
            expr=(m.x - 4) ** 2 + (blk.z - 1) ** 2 - t <= 0
        )
        blk.leyffer_con = pyo.Constraint(
            expr=pyo.sqrt(m.u) * m.x - blk.u * blk.z - 2 <= 0
        )
        blk.dr_con = pyo.Constraint(
            expr=blk.z == m.d0 + blk.u * m.d1
        )
    m.obj = pyo.Objective(expr=m.d0 + m.d1)

    return m


if __name__ == "__main__":
    for make_x_fixed_var in [True, False]:
        model = create_model(
            x=3.5,
            t=0.55,
            u0=9/8,
            u1=13/10,
            make_x_fixed_var=make_x_fixed_var,
        )
        model.write(
            f"model_with_fixed_var_{make_x_fixed_var}.bar",
            io_options={"symbolic_solver_labels": True},
        )
        solver = pyo.SolverFactory("baron")
        solver.solve(model)
        print(f"Solution with make_x_fixed_var={make_x_fixed_var}:")
        print(f"\tz0={pyo.value(model.scenarios[0].z)}")
        print(f"\tz1={pyo.value(model.scenarios[1].z)}")
        print(f"\td0={pyo.value(model.d0)}")
        print(f"\td1={pyo.value(model.d1)}")
```

### Error Message

<!-- If Pyomo reported an error, provide the error message. PLEASE INCLUDE THE ENTIRE STACK TRACE. -->

<!-- If it did not report an error but the output appears incorrect, provide the incorrect output. If there was no error message and no output but the result is incorrect, describe how it does not match what you expect. -->
Console output. Remains the same across different BARON executables (22.11.03, 23.1.5, 23.2.27, 23.3.11)

```console
$ python example.py
Solution with make_x_fixed_var=True:
        z0=1.5220538677594437
        z1=1.7588178025829206
        d0=0.0
        d1=1.3529367712253249
Solution with make_x_fixed_var=False:
        z0=1.5220538677594437
        z1=1.547722557316334
        d0=1.3570408625028816
        d1=0.14667822677957854
```

BARON writer output `model_with_fixed_var_True.bar`. Notice the epigraph constraints (represented in file by `s_igraph_con_1_` and `s_igraph_con_4_` are inconsistent with the original model epigraph constraints.

```
OPTIONS {
Summary: 0;
}

POSITIVE_VARIABLES ONE_VAR_CONST__, d0, d1, scenarios_0__z, scenarios_1__z;

LOWER_BOUNDS{
d0: 0;
d1: 0;
scenarios_0__z: 0;
scenarios_1__z: 0;
}

EQUATIONS c_e_FIX_ONE_VAR_CONST__, s_igraph_con_1_, s_eyffer_con_2_, s__0__dr_con_3_, s_igraph_con_4_, s_eyffer_con_5_, s__1__dr_con_6_;

c_e_FIX_ONE_VAR_CONST__:  ONE_VAR_CONST__  == 1;
s_igraph_con_1_: -0.5 ^ 2 + (scenarios_0__z - 1) ^ 2 + (-0.55) <= 0;
s_eyffer_con_2_: 3.7123106012293743 + (-1.125)*scenarios_0__z - 2 <= 0;
s__0__dr_con_3_: scenarios_0__z - (d0 + 1.125*d1) == 0;
s_igraph_con_4_: -0.5 ^ 2 + (scenarios_1__z - 1) ^ 2 + (-0.55) <= 0;
s_eyffer_con_5_: 3.7123106012293743 + (-1.3)*scenarios_1__z - 2 <= 0;
s__1__dr_con_6_: scenarios_1__z - (d0 + 1.3*d1) == 0;

OBJ: minimize d0 + d1;

STARTING_POINT{
ONE_VAR_CONST__: 1;
}


```

BARON writer output: `model_with_fixed_var_False.bar`. Notice the epigraph constraints (represented in file by `s_igraph_con_1_` and `s_igraph_con_4_` are consistent with the original model epigraph constraints.
```
OPTIONS {
Summary: 0;
}

POSITIVE_VARIABLES ONE_VAR_CONST__, d0, d1, scenarios_0__z, scenarios_1__z;

LOWER_BOUNDS{
d0: 0;
d1: 0;
scenarios_0__z: 0;
scenarios_1__z: 0;
}

EQUATIONS c_e_FIX_ONE_VAR_CONST__, s_igraph_con_1_, s_eyffer_con_2_, s__0__dr_con_3_, s_igraph_con_4_, s_eyffer_con_5_, s__1__dr_con_6_;

c_e_FIX_ONE_VAR_CONST__:  ONE_VAR_CONST__  == 1;
s_igraph_con_1_: 0.25 + (scenarios_0__z - 1) ^ 2 + (-0.55) <= 0;
s_eyffer_con_2_: 3.7123106012293743 + (-1.125)*scenarios_0__z - 2 <= 0;
s__0__dr_con_3_: scenarios_0__z - (d0 + 1.125*d1) == 0;
s_igraph_con_4_: 0.25 + (scenarios_1__z - 1) ^ 2 + (-0.55) <= 0;
s_eyffer_con_5_: 3.7123106012293743 + (-1.3)*scenarios_1__z - 2 <= 0;
s__1__dr_con_6_: scenarios_1__z - (d0 + 1.3*d1) == 0;

OBJ: minimize d0 + d1;

STARTING_POINT{
ONE_VAR_CONST__: 1;
}


```

### Information on your system

Pyomo version: 6.5.1dev0 [#b2101fd](https://github.com/Pyomo/pyomo/tree/b2101fd3c31dd4aeb97ec3f4aebd904e5f6be523)
Python version: 3.9.13
Operating system: Ubuntu 20.04
How Pyomo was installed (PyPI, conda, source): source
Solver (if applicable): BARON


### Additional information

<!-- If you have any additional information, please list it here. -->


<!-- We encourage you to try, as much as possible, to reduce your problem to the minimal example that still reproduces the issue. That would help us a lot in fixing it quickly and effectively!

If you want to ask a question (how to use Pyomo, what it can do, etc.), please refer to our [online documentation](https://github.com/Pyomo/pyomo#getting-help) on ways to get help. -->
