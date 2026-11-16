Database building issue due to inheritance
The following script fails to build a database:

https://github.com/Jammy2211/autolens_workspace_test/blob/main/database/github_issue/build.py

The issue it raises is:

```
"^[[Dremove larTraceback (most recent call last):
  File "/mnt/c/Users/Jammy/Code/PyAuto/autolens_workspace_test/database/github_issue/build.py", line 50, in <module>
    agg.add_directory(directory=path.join("output", database_name))
  File "/mnt/c/Users/Jammy/Code/PyAuto/PyAutoFit/autofit/database/aggregator/aggregator.py", line 419, in add_directory
    scraper.scrape()
  File "/mnt/c/Users/Jammy/Code/PyAuto/PyAutoFit/autofit/database/aggregator/scrape.py", line 62, in scrape
    for fit in self._fits():
  File "/mnt/c/Users/Jammy/Code/PyAuto/PyAutoFit/autofit/database/aggregator/scrape.py", line 89, in _fits
    model = item.model
  File "/mnt/c/Users/Jammy/Code/PyAuto/PyAutoFit/autofit/aggregator/search_output.py", line 161, in model
    self.__model = AbstractPriorModel.from_dict(
  File "/mnt/c/Users/Jammy/Code/PyAuto/PyAutoFit/autofit/mapper/model_object.py", line 243, in from_dict
    from_dict(
  File "/mnt/c/Users/Jammy/Code/PyAuto/PyAutoConf/autoconf/dictable.py", line 156, in from_dict
    return __parsers[type_](dictionary, **kwargs)
  File "/mnt/c/Users/Jammy/Code/PyAuto/PyAutoFit/autofit/mapper/model_object.py", line 243, in from_dict
    from_dict(
  File "/mnt/c/Users/Jammy/Code/PyAuto/PyAutoConf/autoconf/dictable.py", line 156, in from_dict
    return __parsers[type_](dictionary, **kwargs)
  File "/mnt/c/Users/Jammy/Code/PyAuto/PyAutoFit/autofit/mapper/model_object.py", line 243, in from_dict
    from_dict(
  File "/mnt/c/Users/Jammy/Code/PyAuto/PyAutoConf/autoconf/dictable.py", line 156, in from_dict
    return __parsers[type_](dictionary, **kwargs)
  File "/mnt/c/Users/Jammy/Code/PyAuto/PyAutoFit/autofit/mapper/model_object.py", line 213, in from_dict
    return cls_(
TypeError: Isothermal.__init__() got an unexpected keyword argument 'slope'
```

This will be related to how the `slope` parameter of an `Isothermal` is not in its `__init__` constructor:

```
class Isothermal(PowerLaw):
    def __init__(
        self,
        centre: Tuple[float, float] = (0.0, 0.0),
        ell_comps: Tuple[float, float] = (0.0, 0.0),
        einstein_radius: float = 1.0,
    ):
        """
        Represents an elliptical isothermal density distribution, which is equivalent to the elliptical power-law
        density distribution for the value slope: float = 2.0

        Parameters
        ----------
        centre
            The (y,x) arc-second coordinates of the profile centre.
        ell_comps
            The first and second ellipticity components of the elliptical coordinate system.
        einstein_radius
            The arc-second Einstein radius.
        """

        super().__init__(
            centre=centre,
            ell_comps=ell_comps,
            einstein_radius=einstein_radius,
            slope=2.0,
        )
```
