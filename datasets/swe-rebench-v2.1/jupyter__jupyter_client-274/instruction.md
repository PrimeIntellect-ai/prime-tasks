Support metadata in kernel specs
Currently, there's no easy way to track metadata about a kernel beyond what language it supports. Having a display name is helpful, but it'd be nice to allow for programmatic access for more information about the kernel.

For example, internally we use Jupyter in a context where different backends have different functionality available (eg access to different libraries or hardware). It'd be nice to allow a FE to filter the list of available backends if we know a certain library is needed.

Similarly, as new versions of the Jupyter protocol roll out, some FEs will be in a situation where they might need to communicate with backends which speak different protocol versions. Having access to this info programmatically would be nicer than a trial-and-error approach.

/cc @rgbkrk

### Additional contract requirements

- `KernelSpec` in the `jupyter_client.kernelspec` module exposes a public attribute `metadata` that holds a dictionary of additional kernel-specific metadata. When a kernel spec does not provide metadata, `metadata` defaults to an empty dictionary.
