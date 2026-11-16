[feature] Provide conan.tools.microsoft.msvs_toolset equivalent of conans.tools.msvs_toolset
Would it be possible to provide the [msvs_toolset](https://docs.conan.io/en/latest/reference/tools.html#tools-msvs-toolset) function in the `conan` namespace and add support for the `msvc` compiler in it?
I had to workaround the use of the original `msvs_toolset` function in my recent update to the Boost recipe in conan-io/conan-center-index#12819.


- [X] I've read the [CONTRIBUTING guide](https://github.com/conan-io/conan/blob/develop/.github/CONTRIBUTING.md).
