InstrumentBuilder incorrectly marked as internal
https://github.com/open-telemetry/opentelemetry-swift/blob/main/Sources/OpenTelemetrySdk/Metrics/Stable/InstrumentBuilder.swift

This is a little more complicated than just making this public, as some member vars are internal only.

### Additional contract requirements

- `InstrumentBuilder` is a public class in the `OpenTelemetrySdk` module.
- `InstrumentBuilder` declares the public methods `setUnit(_ units: String) -> Self` and `setDescription(_ description: String) -> Self`. Each returns the same builder instance so that calls can be chained.
- The public builder types `LongCounterMeterBuilderSdk`, `DoubleCounterMeterBuilderSdk`, `DoubleGaugeBuilderSdk`, `LongGaugeBuilderSdk`, `LongHistogramMeterBuilderSdk`, `DoubleHistogramMeterBuilderSdk`, `LongUpDownCounterBuilderSdk` and `DoubleUpDownCounterBuilderSdk` are subclasses of `InstrumentBuilder`.
