remove num_samples
the num_samples field on TimeSeries is not in the spec:
https://github.com/NeurodataWithoutBorders/pynwb/blob/f236738e46b541162d2ff3df936f71a6919ec648/src/pynwb/data/nwb.base.yaml#L104-L233

but it is set on TimeSeries:
https://github.com/NeurodataWithoutBorders/pynwb/blob/f236738e46b541162d2ff3df936f71a6919ec648/src/pynwb/base.py#L140
with a bunch of custom logic.

per conversation with @ajtritt I will remove this field.
