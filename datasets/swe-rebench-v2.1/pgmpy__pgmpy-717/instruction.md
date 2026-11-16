Inconsistent behaviour of query in VariableElimination when passing a single variable
If query is passed a single variable rather than a list, it works if the variable name is a single character and fails with an obtuse error otherwise.

The documentation does say to pass a list but there are many examples, ie in the notebooks where a single variable is passed.

Can we either handle passing single variables (ie check and insert them into a list) or check and throw an informative error?

Simple code to reproduce an error below. [HIDDEN]

`
from pgmpy.inference import VariableElimination
from pgmpy.models import BayesianModel
from pgmpy.factors import TabularCPD
model = BayesianModel([('Z', 'Xx')])
cpd_z = TabularCPD(variable='Z', variable_card=2, values=[[0.7, 0.3]])
cpd_x = TabularCPD(variable='Xx', variable_card=2,
                   values=[[0.6, 0.2],
                           [0.4, 0.8]],evidence=['Z'],evidence_card=[2])

model.add_cpds(cpd_z, cpd_x)
model.check_model()

infer = VariableElimination(model)
infer.query('Xx')['Xx']`

### Additional contract requirements

- `VariableElimination.query` raises `TypeError` when `variables` is passed as a scalar string (a single variable name is not silently wrapped into a list).
