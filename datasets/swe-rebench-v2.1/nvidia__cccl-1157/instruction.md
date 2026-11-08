[BUG]: `find_package(CCCL)` cannot be called twice
### Is this a duplicate?

- [X] I confirmed there appear to be no [duplicate issues](https://github.com/NVIDIA/cccl/issues) for this bug and that I agree to the [Code of Conduct](CODE_OF_CONDUCT.md)

### Type of Bug

Something else

### Component

Thrust

### Describe the bug

If `find_package(CCCL)` is invoked multiple times during configuration, the second occurance will trigger a CMake Error as `CCCL::Thrust` already exists, [HIDDEN]

This occurs if the `find_package` calls are in the same `CMakeLists.txt`, or in separate `CMakeLists.txt` with an `add_subdirectory(subdir)` relationship (i.e. if a dependency and a parent package both require CCCL, or if multiple targets in a parent project wish to include/link against CCCL::cccl).

This occurs with the CCCL 2.2.0 distribtued with CUDA 12.2 &* 12.3, and with current `main` (e79b13cf065a02d2310b2e5668c61a2b99689385).

I can work around this by guarding the `find_package` call myself, but that would rely on dependencies also guarding that call in a complex enough project. It can also be avoided by not requesting the thrust component.

### How to Reproduce

1. Create (or ammend) an exisitng CMakeLists.txt to `find_target(CCCL)` twice, with the appropriate location of CCCL on the `CMAKE_PREFIX_PATH`, or set `CCCL_DIR`, or provide appropriate hints.
e.g. in a completley fresh directory with CUDA 12.2 or 12.3 installed
```cmake
cmake_minimum_required(VERSION 3.17 FATAL_ERROR)
project(mwe LANGUAGES CUDA)
# Modern CMake findCUDAToolkit for path hints
find_package(CUDAToolkit REQUIRED)
# Look for CCCL distributed with CUDA
find_package(CCCL CONFIG REQUIRED HINTS ${CUDAToolkit_INCLUDE_DIRS} ${CUDAToolkit_LIBRARY_DIR}/cmake)
# Attempting to find CCCL again results in an error (say if a dependency found it as well), as a target cannot be recreated.
find_package(CCCL CONFIG REQUIRED HINTS ${CUDAToolkit_INCLUDE_DIRS} ${CUDAToolkit_LIBRARY_DIR}/cmake)
```

Or in a subdirectory of the `cccl` repository

```bash
git clone https://github.com/NVIDIA/cccl
cd cccl
mkdir -p cmake-find-target-mwe && cd cmake-find-target-mwe
cat > CMakeLists.txt << EOF
cmake_minimum_required(VERSION 3.17 FATAL_ERROR)
project(mwe LANGUAGES CUDA)
# Modern CMake findCUDAToolkit for path hints
find_package(CUDAToolkit REQUIRED)
# Look for CCCL distributed with CUDA
find_package(CCCL REQUIRED HINTS \${CMAKE_CURRENT_LIST_DIR}/../)
# Attempting to find CCCL again results in an error (say if a dependency found it as well), as a target cannot be recreated.
find_package(CCCL REQUIRED HINTS \${CMAKE_CURRENT_LIST_DIR}/../)
EOF
```
2. Attempt to configure CMake
```bash
cmake -B build
```
3. An error will be thrown, e.g.:
```console
-- Found libcudacxx: /home/ptheywood/code/tmp/cccl/libcudacxx/lib/cmake/libcudacxx/libcudacxx-config.cmake (found suitable version "2.3.0.0", minimum required is "2.3.0.0")
-- Found Thrust: /home/ptheywood/code/tmp/cccl/thrust/thrust/cmake/thrust-config.cmake (found suitable exact version "2.3.0.0")
-- Found CUB: /home/ptheywood/code/tmp/cccl/cub/cub/cmake/cub-config.cmake (found suitable version "2.3.0.0", minimum required is "2.3.0.0")
-- Found CCCL: /home/ptheywood/code/tmp/cccl/lib/cmake/cccl/cccl-config.cmake (found version "2.3.0.0")
CMake Error at /home/ptheywood/code/tmp/cccl/thrust/thrust/cmake/thrust-config.cmake:183 (add_library):
  add_library cannot create imported target "CCCL::Thrust" because another
  target with the same name already exists.
Call Stack (most recent call first):
  /home/ptheywood/code/tmp/cccl/lib/cmake/cccl/cccl-config.cmake:82 (thrust_create_target)
  CMakeLists.txt:8 (find_package)
```

### Expected behavior

Cmake should configure successfully

### Reproduction link

_No response_

### Operating System

Ubuntu Linux 22.04

### nvidia-smi output

_No response_

### NVCC version

_No response_

### Additional contract requirements

- Repeated `find_package(CCCL)` calls during one CMake configuration must succeed when `CCCL::Thrust` already exists; they must not fail because that target is recreated.
