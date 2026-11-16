Introduce `SKBUILD_SABI_VERSION` CMake variable
To follow-up on https://github.com/orgs/scikit-build/discussions/1128#discussioncomment-11489351 answering a question from @minrk, I suggest we introduce the CMake cache variable `SKBUILD_SABI_VERSION` set from the value associated with the `wheel.py-api` setting.

Related documentation:
* https://scikit-build-core.readthedocs.io/en/latest/schema.html
* https://scikit-build-core.readthedocs.io/en/latest/cmakelists.html#limited-api-stable-abi
* https://scikit-build-core.readthedocs.io/en/latest/configuration.html#customizing-the-output-wheel

Related issues & pull requests:
* https://github.com/scikit-build/scikit-build-core/issues/743
* https://github.com/scikit-build/scikit-build-core/pull/957
