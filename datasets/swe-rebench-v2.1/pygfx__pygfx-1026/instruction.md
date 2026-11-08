Bug when dynamically applying or removing env_map
While testing the example in #1004, I found that dynamically applying or removing the env_map was not working correctly. Initially, I thought it was a small issue, assuming we weren't tracking the env_map in MeshStandardMaterial. However, after modifying the code to enable tracking, the program threw the following exception:

```

  File "F:\pygfx\pygfx\renderers\wgpu\engine\pipeline.py", line 135, in get_cached_render_pipeline
    result = device.create_render_pipeline(
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "F:\wgpu-py\wgpu\backends\wgpu_native\_api.py", line 1717, in create_render_pipeline
    id = libf.wgpuDeviceCreateRenderPipeline(self._internal, descriptor)
         ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "F:\wgpu-py\wgpu\backends\wgpu_native\_helpers.py", line 457, in proxy_func
    raise wgpu_error
  File "F:\wgpu-py\wgpu\backends\wgpu_native\_api.py", line 1717, in create_render_pipeline
    id = libf.wgpuDeviceCreateRenderPipeline(self._internal, descriptor)
         ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
wgpu._classes.GPUValidationError: Validation Error

Caused by:
  In wgpuDeviceCreateRenderPipeline
    Error matching ShaderStages(FRAGMENT) shader requirements against the pipeline
      Shader global ResourceBinding { group: 0, binding: 9 } is not available in the pipeline layout
        Binding is missing from the pipeline layout
```

Upon further investigation, I realized the issue was more complicated than expected. Here are my findings:

- When bindings change, the `update_shader_data` method of `PipelineContainer` recollects the bindings, but the [HIDDEN].
- After I [HIDDEN], I found that the shader's `kwargs` were not updated too, which led to some incorrect "macro switches" in the shader. This seems a bit tricky, as we cannot clear all `kwargs` as we did with `_binding_codes`.

### Additional contract requirements

- `BaseShader` (in `pygfx.renderers.wgpu.shader`) must expose attributes named `_template_vars_current` and `_template_vars_bindings`.
- `BaseShader` (in `pygfx.renderers.wgpu.shader`) must expose a method `get_bindings_info(wobject, shared)` that returns the shader's bindings as a dict mapping group index to a dict mapping binding index to a `Binding`. Collecting the bindings this way must refresh the shader's binding-derived state, so that bindings and binding-derived template variables that are no longer produced do not survive from an earlier collection.
- Generated binding code must reflect only the bindings produced by the current collection; declarations for bindings no longer produced must not remain.
- When an `env_map` is present, collected binding code must include `t_env_map`; after removing the `env_map`, the collected binding code must not include `t_env_map`, and `use_IBL` must not remain in `_template_vars_bindings`.
