dir interpolation from hydra into job config is not working
I can set the `second_dir`  from `base_dir`, but `output_subdir` can not in this case.
```
experiment:
  base_dir: ???
  second_dir: ${experiment.base_dir}
hydra:
  output_subdir: ${experiment.base_dir}/.hydra
```
`KeyError: "str interpolation key 'experiment.base_dir' not found"`

Is there any way I can change the hydra config based on current .yaml or some alternately way?
 Thanks!
