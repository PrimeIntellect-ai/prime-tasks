ENH Support Serpent 2.1.32
**Is your feature request related to a problem? Please describe.**
Warning messages like
```
WARN SERPENT Serpent 2.1.32 found in godiva_res.m, but version 2.1.31 is defined in settings
  Attemping to read anyway. Please report strange behaviors/failures to developers.
```
(also a typo) come through. But things seem to work fine.

**Describe the solution you'd like**
Determine what new arguments exist in the result file that should be added to https://github.com/CORE-GATECH-GROUP/serpent-tools/blob/develop/serpentTools/variables.yaml even if we just do something like https://github.com/CORE-GATECH-GROUP/serpent-tools/blob/f61cd104bd997aa80429f1059bbc3669adc18654/serpentTools/variables.yaml#L133

I thought I saw there are also new entries added to the depletion file but none seem to show up

**Describe alternatives you've considered**
Carry on regardless.

Per https://github.com/CORE-GATECH-GROUP/serpent-tools/blob/f61cd104bd997aa80429f1059bbc3669adc18654/serpentTools/settings.py#L108-L116 should check if https://github.com/CORE-GATECH-GROUP/serpent-tools/blob/f61cd104bd997aa80429f1059bbc3669adc18654/serpentTools/parsers/results.py#L43-L55 needs updating or we can copy over

### Additional contract requirements

- Serpent 2.1.32 is an accepted value for the runtime `serpentVersion` setting and can be selected through `serpentTools.settings.rc`.
- `serpentTools.read(filepath)` parses a Serpent results file and returns a reader exposing `resdata` (the parsed result variables) and `metadata`.
- The `xs.variableGroups` setting selects which result-variable groups are read.
- For Serpent 2.1.32, `BURN_RANDOMIZE_DATA` is exposed in `resdata` as `burnRandomizeData`.
- For Serpent 2.1.32, the `burnup-coeff` variable group includes `BURN_DAYS`, exposed in `resdata` as `burnDays`, and `FIMA`, exposed in `resdata` as `fima`.
- For Serpent 2.1.32, the `energy-deposition` variable group contains `EDEP_MODE`, `EDEP_DELAYED`, `EDEP_KEFF_CORR`, `EDEP_LOCAL_EGD`, `EDEP_COMP`, and `EDEP_CAPT_E`, exposed in `resdata` as `edepMode`, `edepDelayed`, `edepKeffCorr`, `edepLocalEgd`, `edepComp`, and `edepCaptE`, respectively.
