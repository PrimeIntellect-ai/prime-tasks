Raise OptionError if "SEI on cracks" is "true" but cracking isn't enabled.
If you do e.g.
```python3
model = pybamm.lithium_ion.SPMe(
    {
        "SEI": "solvent-diffusion limited",
        "SEI porosity change": "true",
        "lithium plating": "partially reversible",
        "lithium plating porosity change": "true",  # alias for "SEI porosity change"
        "particle mechanics": ("swelling only", "swelling only"),
        "SEI on cracks": "true",
        "loss of active material": "stress-driven",
    }
)
```
you get a `ZeroDivisionError`. It doesn't make sense to have SEI n cracks if there are no cracks, so we should catch this and raise an `OptionError`
