Sensitivity Mapping `unique_tag` path
In the following example:

https://github.com/Jammy2211/autofit_workspace/blob/release/scripts/features/sensitivity_mapping.py

I create a `search` with the `unique_tag=hello`:

```
search = af.DynestyStatic(
    path_prefix=path.join("features", "sensitivity_mapping", "single_gaussian"),
    unique_tag="hello",
    nlive=100,
)
```

The `unique_tag` is correctly used to set up the a folder with that word in the paths:

![image](https://github.com/user-attachments/assets/36f9bfe2-6761-4a1c-bc22-3fea33da22d7)

I then perform sensitivity mapping:

```
paths = af.DirectoryPaths(
    path_prefix=path.join("features"),
    unique_tag="hello",
    name="sensitivity_mapping",
)

sensitivity = af.Sensitivity(
    paths=paths,
    simulation_instance=simulation_instance,
    base_model=base_model,
    perturb_model=perturb_model,
    simulate_cls=Simulate(),
    base_fit_cls=BaseFit(analysis_cls=Analysis),
    perturb_fit_cls=PerturbFit(analysis_cls=Analysis),
    number_of_steps=2,
    number_of_cores=2,
)
sensitivity_result = sensitivity.run()
```

![image](https://github.com/user-attachments/assets/8ccbbadf-eded-446d-9ccb-717af42b4812)


Basically, the folder `5d41402abc4b2a76b9719d911017c592` should of been placed in the `hello` folder.

However, the `unique_tag` is not used to create the folder where the sensitivity mapping results are stored:
