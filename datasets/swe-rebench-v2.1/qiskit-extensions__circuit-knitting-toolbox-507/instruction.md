Support SamplerV2
The circuit cutting post-processing uses the `SamplerResult` objects output from `SamplerV1` directly; however, `SamplerV2` will return `PrimitiveResult` objects, so our post-processing should support both types of outputs from the two different sampler interfaces

https://github.com/Qiskit/qiskit/blob/61181ce0681129f9a1d5af43122484f8b6da1bbc/qiskit/primitives/base/base_sampler.py#L231
