marginal_counts is broken for pulse results
<!-- ⚠️ If you do not respect this template, your issue will be closed -->
<!-- ⚠️ Make sure to browse the opened and closed issues -->

### Information

- **Qiskit Terra version**: 0.18.0
- **Python version**: 3.9
- **Operating system**: OSx

### What is the current behavior?
`marginal_counts` is broken for pulse jobs. I


### Steps to reproduce the problem
```python
from qiskit import pulse, QuantumCircuit, schedule, transpile, execute, IBMQ
from qiskit.result import marginal_counts


IBMQ.load_account()
provider = IBMQ.get_provider(hub='ibm-q', group='open', project='main')
backend = provider.get_backend('ibmq_armonk')

qc = QuantumCircuit(1,1)
qc.measure(0, 0)

job = backend.run(schedule(transpile(qc, backend), backend))
marginal_counts(job.result(), indices=[0])
```
Gives output
```
---------------------------------------------------------------------------
AttributeError                            Traceback (most recent call last)
<ipython-input-6-8e897d2c2a54> in <module>
     11
     12 job = backend.run(schedule(transpile(qc, backend), backend))
---> 13 marginal_counts(job.result(), indices=[0])

~/opt/anaconda3/envs/python39/lib/python3.9/site-packages/qiskit/result/utils.py in marginal_counts(result, indices, inplace, format_marginal)
     55             experiment_result.data.counts = new_counts_hex
     56             experiment_result.header.memory_slots = len(indices)
---> 57             csize = experiment_result.header.creg_sizes
     58             experiment_result.header.creg_sizes = _adjust_creg_sizes(csize, indices)
     59         return result

AttributeError: 'QobjExperimentHeader' object has no attribute 'creg_sizes'
```


### What is the expected behavior?



### Suggested solutions
It seems like it is assuming `creg` will be present in the header. This is not true for pulse jobs which do not have classical registers and therefore this field won't be present. The fix should make marginal_counts work when the header is empty.
