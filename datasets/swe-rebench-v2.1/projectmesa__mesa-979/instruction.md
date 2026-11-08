BatchRunner swaps content of variable_params columns, only in random proportion of executions
**Describe the bug**
When using BatchRunner, and calling get_model_vars_dataframe(), the contents of the columns in the output  of two variable parameters are swapped: the column heads stay the same, but matches with the parameter values of another parameter. I cannot tell yet whether it is just the columns of the DataFrame that is wrong, or also the batch run with the wrong values.

The remarkable thing is: when I execute my script several times, with the same code, it only happens in a number of executions. Maybe the behaviour of the bug is dependent on a random value?

**Expected behavior**
I expect the BatchRunner model vars dataframe to give back the variable parameter values that correspond with a certain parameter. Instead, the parameter values of one parameter are swapped with the parameter values of another parameter.

**To Reproduce**
I do not have a minimum working example. I have some code which depends on my specific model:

```
from mesa.batchrunner import BatchRunner
from constants import HEIGHT, WIDTH, PROPORTION_L2, SUFFIX_PROB, CAPACITY_L1, CAPACITY_L2, \
                        DROP_SUBJECT_PROB, DROP_OBJECT_PROB, MIN_BOUNDARY_FEATURE_DIST
from Model import Model

fixed_params = {
    "height": HEIGHT,
    "width": WIDTH,
    "proportion_l2": PROPORTION_L2,
    "suffix_prob": SUFFIX_PROB,
    "capacity_l1": CAPACITY_L1,
    "capacity_l2": CAPACITY_L2,
    "drop_subject_prob": DROP_SUBJECT_PROB,
    "drop_object_prob": DROP_OBJECT_PROB,
    "min_boundary_feature_dist": MIN_BOUNDARY_FEATURE_DIST
}

variable_params = {"proportion_l2":[0.0, 0.2, 0.5], "capacity_l1": [0.0,1.0,2.0,5.0]}

for k in variable_params:
    del fixed_params[k]

stats = {"global_filled_prefix_l1": lambda m: m.global_filled_prefix_l1,
         "global_filled_suffix_l1": lambda m: m.global_filled_suffix_l1,
         "global_filled_prefix_l2": lambda m: m.global_filled_prefix_l2,
         "global_filled_suffix_l2": lambda m: m.global_filled_suffix_l2}

batch_run = BatchRunner(
    Model,
    variable_params,
    fixed_params,
    iterations=1,
    max_steps=1,
    model_reporters=stats
)

batch_run.run_all()
cols = list(variable_params.keys()) + list(stats.keys())
run_data = batch_run.get_model_vars_dataframe()
run_data = run_data[cols]
print(run_data)
run_data.to_csv("evaluation.tsv", sep="\t")
```

It gives the following output:
```
12it [00:02,  5.13it/s]
    proportion_l2  capacity_l1  global_filled_prefix_l1  global_filled_suffix_l1  global_filled_prefix_l2  global_filled_suffix_l2
0             0.0          0.0                      0.0                      0.0                      0.0                      0.0
1             1.0          0.0                      0.0                      0.0                      0.0                      0.0
2             2.0          0.0                      0.0                      0.0                      0.0                      0.0
3             5.0          0.0                      0.0                      0.0                      0.0                      0.0
4             0.0          0.2                      0.0                      0.0                      0.0                      0.0
5             1.0          0.2                      0.0                      0.0                      0.0                      0.0
6             2.0          0.2                      0.0                      0.0                      0.0                      0.0
7             5.0          0.2                      0.0                      0.0                      0.0                      0.0
8             0.0          0.5                      0.0                      0.0                      0.0                      0.0
9             1.0          0.5                      0.0                      0.0                      0.0                      0.0
10            2.0          0.5                      0.0                      0.0                      0.0                      0.0
11            5.0          0.5                      0.0                      0.0                      0.0                      0.0
```

In the output, the values of ther parameters `capacity_l1` and `proportion_l2` have been swapped, if you compare them how these have been initialized.

**Additional context**
The bug occurs on two different Ubuntu machines, with mesa 0.8.7 or 0.8.8. The bug doesn't occur in mesa 0.8.6.
