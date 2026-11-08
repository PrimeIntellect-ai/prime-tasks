Time_duration (formerly target_duration) is broken due to the phase-info update.
### Description

Time_duration (formerly target_duration) is broken due to the phase-info update.

### Example

See the fixed duration reserve mission example.

### Aviary Version

0.10*

### Relevant environment information

_No response_

### Additional contract requirements

- When phase info supplies a phase’s `time_duration`, the phase must end at that specified elapsed duration. This applies to the fixed-duration reserve-mission use case referenced in the issue.
