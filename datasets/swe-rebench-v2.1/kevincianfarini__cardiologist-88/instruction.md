Consider introducing `RecurringJobMode.Skip`
Currently we allow both concurrent execution of pulses and cancellation of pulses which would otherwise experience backpressure. Another option for coping with backpressure which we can't apply is to skip the current item if the previous one is still executing.

### Additional contract requirements

- For a 100-millisecond interval pulse with three emissions and a 250-millisecond action in `RecurringJobMode.Skip`, the only executed scheduled instant must be `Instant.fromEpochMilliseconds(100)`.
- In `RecurringJobMode.Skip`, a pulse received while the preceding action is still running is dropped without overlapping with or cancelling that action. A pulse received when no action is active remains eligible to run.
