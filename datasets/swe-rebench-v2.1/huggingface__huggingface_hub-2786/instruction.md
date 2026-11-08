Add `text-to-video` task and replicate's support for `text-to-speech`.

### Additional contract requirements

- The `replicate` provider must support the `text-to-video` task: `"text-to-video"` must be a key in the provider's `SUPPORTED_MODELS` mapping, and `ReplicateTask("text-to-video")` must build requests for the model `genmo/mochi-1-preview`.
- The `replicate` provider must support the `text-to-speech` task: `"text-to-speech"` must be a key in the provider's `SUPPORTED_MODELS` mapping, and `ReplicateTask("text-to-speech")` must build requests for the model `OuteAI/OuteTTS-0.3-500M`.
- The provider registry must expose both tasks: `get_provider_helper("replicate", "text-to-video")` and `get_provider_helper("replicate", "text-to-speech")` must return helpers whose `task` attribute equals the requested task.
- `ReplicateTask(task)` must raise a `ValueError` when preparing a request for a task that is not a key in `SUPPORTED_MODELS`.
- Text-to-video inference must also be available through the `InferenceClient` task API, accepting a prompt and returning the generated video bytes.
