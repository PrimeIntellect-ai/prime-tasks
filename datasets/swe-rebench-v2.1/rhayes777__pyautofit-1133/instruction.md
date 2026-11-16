Compute latent variable API issue?
The following example:

https://github.com/Jammy2211/autolens_workspace/blob/main/scripts/results/workflow/csv_make.py

Has the following function:

```
    class AnalysisLatent(al.AnalysisImaging):
        def compute_latent_variables(self, instance):
            if hasattr(instance.galaxies.lens, "shear"):
                magnitude, angle = al.convert.shear_magnitude_and_angle_from(
                    gamma_1=instance.galaxies.lens.shear.gamma_1,
                    gamma_2=instance.galaxies.lens.shear.gamma_2,
                )

                return {
                    "galaxies.lens.shear.magnitude": magnitude,
                    "galaxies.lens.shear.angle": angle,
                }

    analysis = AnalysisLatent(dataset=dataset)
```

But the fit gives the following exception:

```
2025-05-02 13:37:56,035 - results - INFO - Fit Running: Updating results after 300 iterations (see output folder).
Traceback (most recent call last):
  File "/mnt/c/Users/Jammy/Code/PyAuto/autolens_workspace/scripts/results/workflow/csv_make.py", line 122, in <module>
    result = search.fit(model=model, analysis=analysis)
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/mnt/c/Users/Jammy/Code/PyAuto/PyAutoFit/autofit/non_linear/search/abstract_search.py", line 595, in fit
    result = self.start_resume_fit(
             ^^^^^^^^^^^^^^^^^^^^^^
  File "/mnt/c/Users/Jammy/Code/PyAuto/PyAutoFit/autofit/non_linear/search/abstract_search.py", line 120, in decorated
    return func(self, *args, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/mnt/c/Users/Jammy/Code/PyAuto/PyAutoFit/autofit/non_linear/search/abstract_search.py", line 745, in start_resume_fit
    search_internal = self._fit(
                      ^^^^^^^^^^
  File "/mnt/c/Users/Jammy/Code/PyAuto/PyAutoFit/autofit/non_linear/search/nest/nautilus/search.py", line 149, in _fit
    search_internal = self.fit_multiprocessing(
                      ^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/mnt/c/Users/Jammy/Code/PyAuto/PyAutoFit/autofit/non_linear/search/nest/nautilus/search.py", line 261, in fit_multiprocessing
    return self.call_search(search_internal=search_internal, model=model, analysis=analysis)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/mnt/c/Users/Jammy/Code/PyAuto/PyAutoFit/autofit/non_linear/search/nest/nautilus/search.py", line 333, in call_search
    self.perform_update(
  File "/mnt/c/Users/Jammy/Code/PyAuto/PyAutoFit/autofit/non_linear/search/abstract_search.py", line 1028, in perform_update
    self.paths.save_latent_samples(latent_samples)
  File "/mnt/c/Users/Jammy/Code/PyAuto/PyAutoFit/autofit/non_linear/paths/directory.py", line 272, in save_latent_samples
    self._save_samples(latent_samples, name="latent")
  File "/mnt/c/Users/Jammy/Code/PyAuto/PyAutoFit/autofit/non_linear/paths/directory.py", line 295, in _save_samples
    samples.save_covariance_matrix(directory / "covariance.csv")
  File "/mnt/c/Users/Jammy/Code/PyAuto/PyAutoFit/autofit/non_linear/samples/pdf.py", line 397, in save_covariance_matrix
    np.savetxt(filename, self.covariance_matrix, delimiter=",")
                         ^^^^^^^^^^^^^^^^^^^^^^
  File "/mnt/c/Users/Jammy/Code/PyAuto/PyAutoFit/autofit/non_linear/samples/pdf.py", line 376, in covariance_matrix
    if len(self.parameter_lists) == 1:
           ^^^^^^^^^^^^^^^^^^^^
  File "/mnt/c/Users/Jammy/Code/PyAuto/PyAutoFit/autofit/non_linear/samples/samples.py", line 215, in parameter_lists
    result.append(sample.parameter_lists_for_paths(tuples))
                  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/mnt/c/Users/Jammy/Code/PyAuto/PyAutoFit/autofit/non_linear/samples/sample.py", line 114, in parameter_lists_for_paths
    raise KeyError(
KeyError: "Could not find any of the following keys in kwargs (('galaxies', 'magnitude'),)"
```

I guess multiple full stops are not supported?
