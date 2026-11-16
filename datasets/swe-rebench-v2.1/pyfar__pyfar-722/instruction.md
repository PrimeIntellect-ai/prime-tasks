dsp.normalize's reference_methods "power" and "energy" behave unexpectedly
## General

* pyfar version: 0.6.8 (issue persists in current code though)
* Python version: 3.12.4
* Operating System: windows
* Did you install pyfar via pip: yes

## Description

I tried to normalize several signals of different length to the same total energy using pyfar. I expected this to be possible using
```
pyfar.dsp.normalize(signal, reference_method="energy", target=1)
```
such that each signal would end up with a total energy of 1. However, since the input is a pressure signal and the reference value is energetic, the output signals do not have energies of 1. In fact, they do not even have the same energies:

For instance, with an input signal with an energy of 20, normalize will output a signal with an energy of 0.05 (1/20), whereas an input energy of 5 will output an energy of 0.2 (1/5).
I talked about this with @f-brinkmann and we both think the function call above should return a signal with an energy of 1.
So, when the `reference_method` is set to "power" or "energy", we believe the signal should be [HIDDEN]

## Code Example
```py
shorter = pf.signals.noise(2000, rms=0.1)
longer = pf.signals.noise(4000, rms=0.1)

for input_signal, name in [(shorter, "shorter"), (longer, "longer")]:
    input_energy = pf.dsp.energy(input_signal)
    output_signal = pf.dsp.normalize(input_signal, reference_method="energy")
    output_energy = pf.dsp.energy(output_signal)

    print(f"{name}:")
    print(f"  in:  {input_energy}")
    print(f"  out: {output_energy}")
```

Outputs:
```
shorter:
  in:  [20.]
  out: [0.05]
longer:
  in:  [40.]
  out: [0.025]
```

### Additional contract requirements

- When `reference_method` is `"energy"` or `"power"`, the corresponding energy or power of the normalized signal, with the selected `channel_handling`, must equal `target`, including for non-unit targets.
