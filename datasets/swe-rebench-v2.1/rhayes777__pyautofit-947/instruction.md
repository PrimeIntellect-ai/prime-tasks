Model Components With No Free Parameters In the Database
The following test script:

https://github.com/Jammy2211/autolens_workspace_test/blob/main/scripts/database/scrape/slam_pix.py

Gives the following error:

```
Traceback (most recent call last):
  File "/mnt/c/Users/Jammy/Results/slacs/paper/mge.py", line 63, in <module>
    ml_instances = [samps.max_log_likelihood() for samps in agg.values("samples")]
  File "/mnt/c/Users/Jammy/Results/slacs/paper/mge.py", line 63, in <listcomp>
    ml_instances = [samps.max_log_likelihood() for samps in agg.values("samples")]
  File "/mnt/c/Users/Jammy/Code/PyAuto/PyAutoFit/autofit/non_linear/samples/interface.py", line 34, in wrapper
    return self._instance_from_vector(vector)
  File "/mnt/c/Users/Jammy/Code/PyAuto/PyAutoFit/autofit/non_linear/samples/samples.py", line 64, in _instance_from_vector
    instance = super()._instance_from_vector(vector)
  File "/mnt/c/Users/Jammy/Code/PyAuto/PyAutoFit/autofit/non_linear/samples/interface.py", line 217, in _instance_from_vector
    return self.model.instance_from_vector(vector=vector, ignore_prior_limits=True)
  File "/mnt/c/Users/Jammy/Code/PyAuto/PyAutoFit/autofit/mapper/prior_model/abstract.py", line 776, in instance_from_vector
    return self.instance_for_arguments(
  File "/mnt/c/Users/Jammy/Code/PyAuto/PyAutoFit/autofit/mapper/prior_model/abstract.py", line 1316, in instance_for_arguments
    return self._instance_for_arguments(
  File "/mnt/c/Users/Jammy/Code/PyAuto/PyAutoFit/autofit/mapper/prior_model/collection.py", line 249, in _instance_for_arguments
    value = value.instance_for_arguments(arguments)
  File "/mnt/c/Users/Jammy/Code/PyAuto/PyAutoFit/autofit/mapper/prior_model/abstract.py", line 1316, in instance_for_arguments
    return self._instance_for_arguments(
  File "/mnt/c/Users/Jammy/Code/PyAuto/PyAutoFit/autofit/mapper/prior_model/collection.py", line 249, in _instance_for_arguments
    value = value.instance_for_arguments(arguments)
  File "/mnt/c/Users/Jammy/Code/PyAuto/PyAutoFit/autofit/mapper/prior_model/abstract.py", line 1316, in instance_for_arguments
    return self._instance_for_arguments(
  File "/mnt/c/Users/Jammy/Code/PyAuto/PyAutoFit/autofit/mapper/prior_model/prior_model.py", line 428, in _instance_for_arguments
    ] = prior_model.instance_for_arguments(
  File "/mnt/c/Users/Jammy/Code/PyAuto/PyAutoFit/autofit/mapper/prior_model/abstract.py", line 1316, in instance_for_arguments
    return self._instance_for_arguments(
  File "/mnt/c/Users/Jammy/Code/PyAuto/PyAutoFit/autofit/mapper/prior_model/prior_model.py", line 454, in _instance_for_arguments
    result = self.cls(**constructor_arguments)
TypeError: Pixelization.__init__() missing 1 required positional argument: 'mesh'
```

This is because I updated the model composition of a `Pixelization` to be as follows:

```
pixelization = af.Model(
    al.Pixelization,
    image_mesh=al.image_mesh.Overlay(shape=(30, 30)),
    mesh=al.mesh.Delaunay(),
    regularization=al.reg.Constant,
)
```

Notably, the `mesh` input and object does not have free parameters.

The code `mesh=al.mesh.Delaunay()` tells the code to use the delaunay functionality, but in this particular example it does not have any free parameters.

Can you update autofit database functionality to smoothly handle objects like this?
