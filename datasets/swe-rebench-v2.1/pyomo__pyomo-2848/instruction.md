UnboundLocalError in FBBT _prop_bnds_leaf_to_root_GeneralExpression()
## Summary

`UnboundLocalError: local variable 'expr_ub' referenced before assignment` is raised when running DISPATCHES code in after Pyomo 6.6.0 was released.

[HIDDEN]

https://github.com/Pyomo/pyomo/blob/d39671ef28a76ed18f6034af0013af49f14cf444/pyomo/contrib/fbbt/fbbt.py#L446-L450

(the code above is from the 6.6.0 tag)

### Steps to reproduce the issue

```sh
conda create --yes --name test-dispatches-202 python=3.9 && conda activate test-dispatches-202
pip install "dispatches @ git+https://github.com/gmlc-dispatches/dispatches@main" && idaes get-extensions
pip show pyomo idaes-pse  # should show Pyomo 6.6.0, IDAES 2.0.0
pytest --pyargs dispatches -k test_usc_discharge_model
```

### Error Message

```log
model = <pyomo.core.base.PyomoModel.ConcreteModel object at 0x7fbee7f3dc70>

    @pytest.mark.integration
    def test_usc_discharge_model(model):

        # Unfix disjuncts
        discharge_usc.unfix_disjuncts_post_initialization(model)

        # Add missing functions to complete the discharge model (add bounds
        # and disjunctions)
        discharge_usc.add_bounds(model, power_max=power_max)

        # Add design optimization problem
        discharge_usc.model_analysis(model, heat_duty=heat_duty)

        opt = SolverFactory('gdpopt')
        _prop_bnds_root_to_leaf_map[ExternalFunctionExpression] = lambda x, y, z: None

>       result = opt.solve(
            model,
            tee=False,
            algorithm='RIC',
            mip_solver='cbc',
            nlp_solver='ipopt',
            init_algorithm="no_init",
            subproblem_presolve=False,
            nlp_solver_args=dict(options={"max_iter": 150})
        )

dispatches/case_studies/fossil_case/ultra_supercritical_plant/storage/tests/test_discharge_usc_powerplant.py:128:
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
/opt/hostedtoolcache/Python/3.9.16/x64/lib/python3.9/site-packages/pyomo/contrib/gdpopt/GDPopt.py:141: in solve
    return SolverFactory(_supported_algorithms[algorithm][0]).solve(model, **kwds)
/opt/hostedtoolcache/Python/3.9.16/x64/lib/python3.9/site-packages/pyomo/contrib/gdpopt/ric.py:60: in solve
    return super().solve(model, **kwds)
/opt/hostedtoolcache/Python/3.9.16/x64/lib/python3.9/site-packages/pyomo/contrib/gdpopt/algorithm_base_class.py:130: in solve
    self._solve_gdp(model, config)
/opt/hostedtoolcache/Python/3.9.16/x64/lib/python3.9/site-packages/pyomo/contrib/gdpopt/ric.py:85: in _solve_gdp
    mip_feasible = solve_MILP_discrete_problem(
/opt/hostedtoolcache/Python/3.9.16/x64/lib/python3.9/site-packages/pyomo/contrib/gdpopt/solve_discrete_problem.py:44: in solve_MILP_discrete_problem
    fbbt(
/opt/hostedtoolcache/Python/3.9.16/x64/lib/python3.9/site-packages/pyomo/contrib/fbbt/fbbt.py:1559: in fbbt
    _new_var_bounds = _fbbt_block(comp, config)
/opt/hostedtoolcache/Python/3.9.16/x64/lib/python3.9/site-packages/pyomo/contrib/fbbt/fbbt.py:1445: in _fbbt_block
    _new_var_bounds = _fbbt_con(c, config)
/opt/hostedtoolcache/Python/3.9.16/x64/lib/python3.9/site-packages/pyomo/contrib/fbbt/fbbt.py:1333: in _fbbt_con
    visitorA.dfs_postorder_stack(con.body)
/opt/hostedtoolcache/Python/3.9.16/x64/lib/python3.9/site-packages/pyomo/core/expr/visitor.py:924: in dfs_postorder_stack
    ans = self.visit(_obj, _result)
/opt/hostedtoolcache/Python/3.9.16/x64/lib/python3.9/site-packages/pyomo/contrib/fbbt/fbbt.py:1114: in visit
    _prop_bnds_leaf_to_root_map[node.__class__](
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _

node = <pyomo.core.base.expression.ScalarExpression object at 0x7fbeedfb7130>
bnds_dict = <pyomo.common.collections.component_map.ComponentMap object at 0x7fbee4c7eca0>
feasibility_tol = 1e-08

    def _prop_bnds_leaf_to_root_GeneralExpression(node, bnds_dict, feasibility_tol):
        """
        Propagate bounds from children to parent

        Parameters
        ----------
        node: pyomo.core.base.expression._GeneralExpressionData
        bnds_dict: ComponentMap
        feasibility_tol: float
            If the bounds computed on the body of a constraint violate the bounds of the constraint by more than
            feasibility_tol, then the constraint is considered infeasible and an exception is raised. This tolerance
            is also used when performing certain interval arithmetic operations to ensure that none of the feasible
            region is removed due to floating point arithmetic and to prevent math domain errors (a larger value
            is more conservative).
        """
        if node.expr.__class__ in native_types:
            [HIDDEN]
        else:
            expr_lb, expr_ub = bnds_dict[node.expr]
>       bnds_dict[node] = (expr_lb, expr_ub)
E       UnboundLocalError: local variable 'expr_ub' referenced before assignment
```

### Information on your system

Pyomo version: 6.6.0
Python version: 3.8--3.9
Operating system: Ubuntu, Windows Server (GitHub Actions runners)
How Pyomo was installed (PyPI, conda, source): PyPI
Solver (if applicable): gdpopt


### Additional information

<!-- If you have any additional information, please list it here. -->


<!-- We encourage you to try, as much as possible, to reduce your problem to the minimal example that still reproduces the issue. That would help us a lot in fixing it quickly and effectively!

If you want to ask a question (how to use Pyomo, what it can do, etc.), please refer to our [online documentation](https://github.com/Pyomo/pyomo#getting-help) on ways to get help. -->

### Additional contract requirements

- During FBBT bound propagation, a `GeneralExpression` whose wrapped expression is a native value must be handled without raising `UnboundLocalError`, and bounds must be propagated correctly to the parent expression.
