Remove nodes without CPD
[This line](https://github.com/pgmpy/pgmpy/blob/dev/pgmpy/models/BayesianModel.py#L165) checks whether the node has CPD by getting its CPD. However, get_cpds will raise an error if the node doesn't have a CPD. So that line will break when there is no CPD for the node.

@ankurankan I can fix it, but I need your input on whether to have get_cpds return None if the CPD doesn't exist, or to check the existence of CPD in other ways?
