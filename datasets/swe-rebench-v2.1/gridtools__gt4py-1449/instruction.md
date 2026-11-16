tuples of fields of different locations violate ITIR
The following stencil from Icon4Py currently fails when using temporaries:
```python
@field_operator
def _mo_velocity_advection_stencil_17(
    e_bln_c_s: Field[[CEDim], wpfloat],
    z_v_grad_w: Field[[EdgeDim, KDim], vpfloat],
    ddt_w_adv: Field[[CellDim, KDim], vpfloat],
) -> Field[[CellDim, KDim], vpfloat]:
    z_v_grad_w_wp, ddt_w_adv_wp = z_v_grad_w, ddt_w_adv
    ...
```
The resulting ITIR contains the following:
```
(↑(λ(__arg0, __arg1) → {·__arg0, ·__arg1}))(z_v_grad_w, ddt_w_adv)
```
However since `z_v_grad_w` and `ddt_w_adv` live on different domains this is invalid. This currently breaks the temporary pass (as type inference fails). However when all lifts are force inlined the problem disappears so it never surfaced before.
