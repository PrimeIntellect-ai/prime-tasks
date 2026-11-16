Two lines starting with macros are formatted as though they are one line
This

```julia
@doc _unit_docstr("diameterPart", "diameter part", "1/60 rad", "rad")
@unit diameterPartᵃ "diameterPart" DiameterPartᵃ (1radᵃ // 60) false
```

gets formatted to this mess (which even violates the line length)

```julia
@doc _unit_docstr("diameterPart", "diameter part", "1/60 rad", "rad") @unit diameterPartᵃ "diameterPart" DiameterPartᵃ (
    1radᵃ//60
) false
```
