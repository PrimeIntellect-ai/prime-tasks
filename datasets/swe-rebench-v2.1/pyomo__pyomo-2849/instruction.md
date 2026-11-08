IndexedComponent_slice wildcard methods argspec changes cause TypeError in 6.6.0
## Summary

We started noticing errors in unrelated PRs (e.g. https://github.com/watertap-org/watertap/actions/runs/5084274162/jobs/9136351337?pr=1037) after Pyomo 6.6.0 was released.

From a quick search, it looks like #2829 added a `sort` positional argument to the `wildcard_items()`, `_keys()`, and `_values()` of `pyomo.core.base.indexed_component_slice.IndexedComponent_slice`:

https://github.com/Pyomo/pyomo/blob/dfe0f81371d30bb8cd4cc39b3b43b449ec32cea9/pyomo/core/base/indexed_component_slice.py#L351

Compare with the previous API (6.5.0 tag):

https://github.com/Pyomo/pyomo/blob/2dda659e74fa1eed4ceb9d4f34336890e7998d38/pyomo/core/base/indexed_component_slice.py#L323

This causes code using the previous API with no args to raise a `TypeError` under Pyomo 6.6.0.

### Steps to reproduce the issue

The following snippet works fine using Pyomo 6.5.0, but raises a `TypeError` in 6.6.0:

```py
    def _get_performance_contents(self, time_point=0):
        var_dict = {}

        for k, v in self._perf_var_dict.items():
            if k in ["Solute Removal", "Reaction Extent", "Rejection"]:
                for j, vd in v[time_point, :].wildcard_items():
                    var_dict[f"{k} [{j}]"] = vd
            elif v.is_indexed():
                var_dict[k] = v[time_point]
            else:
                var_dict[k] = v

        return {"vars": var_dict}
```

### Error Message

```log
 /home/runner/work/watertap/watertap/watertap/core/zero_order_base.py:321: TypeError
__________ TestSecondaryTreatmentWWTPZO_w_default_removal.test_report __________

self = <watertap.unit_models.zero_order.tests.test_secondary_treatment_wwtp_zo.TestSecondaryTreatmentWWTPZO_w_default_removal object at 0x7f7fe5c12890>
model = <pyomo.core.base.PyomoModel.ConcreteModel object at 0x7f7fccaf3fb0>

    @pytest.mark.component
    def test_report(self, model):

>       model.fs.unit.report()

/home/runner/work/watertap/watertap/watertap/unit_models/zero_order/tests/test_secondary_treatment_wwtp_zo.py:174:
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
/usr/share/miniconda/envs/watertap-dev/lib/python3.7/site-packages/idaes/core/base/process_base.py:324: in report
    performance = self._get_performance_contents(time_point=time_point)
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _

self = <idaes.core.base.process_block._ScalarSecondaryTreatmentWWTPZO object at 0x7f7fce174dd0>
time_point = 0.0

    def _get_performance_contents(self, time_point=0):
        var_dict = {}

        for k, v in self._perf_var_dict.items():
            if k in ["Solute Removal", "Reaction Extent", "Rejection"]:
>               for j, vd in v[time_point, :].wildcard_items():
E               TypeError: wildcard_items() missing 1 required positional argument: 'sort'

```

### Information on your system

Pyomo version: 6.6.0
Python version: 3.7--3.10
Operating system: Ubuntu 22.04, Microsoft Windows Server 2019 (GitHub Actions runners)
How Pyomo was installed (PyPI, conda, source): PyPI
Solver (if applicable): N/A


### Additional information

Sample complete GitHub Actions run log: https://github.com/watertap-org/watertap/actions/runs/5084274162/jobs/9136351976?pr=1037


<!-- We encourage you to try, as much as possible, to reduce your problem to the minimal example that still reproduces the issue. That would help us a lot in fixing it quickly and effectively!

If you want to ask a question (how to use Pyomo, what it can do, etc.), please refer to our [online documentation](https://github.com/Pyomo/pyomo#getting-help) on ways to get help. -->
