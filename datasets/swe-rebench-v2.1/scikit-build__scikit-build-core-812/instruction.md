CMake SDist only could skip sdist step
Currently I don't think it's useful to use CMake only in the SDist only step, as if someone builds a wheel from source, the SDist step won't run. We should consider this use case, and see if there's a way (maybe with overrides) to add controls for Source vs. from SDist builds.

I think `if.from-sdist` would do it?

### Additional contract requirements

- The override condition `if.from-sdist` must be supported. It is true when the project directory contains a `PKG-INFO` file (as an unpacked sdist does) and false otherwise.
- Overrides conditioned on `if.from-sdist` must be able to give `wheel.cmake` and `sdist.cmake` different values for builds from source and builds from an sdist, so that CMake can be used only in the sdist step.
