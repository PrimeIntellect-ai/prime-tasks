Shouldn't Sir classify changes in test modules by "tests" label?
Now we have only this pattern:
https://github.com/python/bedevere/blob/84a2aa48abca4038086e78ea6871f68095f33647/bedevere/prtype.py#L48-L49
to trigger "tests" label.

I believe we could add also [HIDDEN] alternative to mark so also changes in test modules.  PR examples:
* https://github.com/python/cpython/pull/111624
* https://github.com/python/cpython/pull/111591
* https://github.com/python/cpython/pull/111709

It seems to be a safe choice:
```
$ find . -name '_test*'
./Programs/_testembed.c
./PCbuild/_testconsole.vcxproj.filters
./PCbuild/_testclinic.vcxproj
./PCbuild/_testmultiphase.vcxproj
./PCbuild/_testembed.vcxproj
./PCbuild/_testimportmultiple.vcxproj.filters
./PCbuild/_testconsole.vcxproj
./PCbuild/_testbuffer.vcxproj
./PCbuild/_testsinglephase.vcxproj.filters
./PCbuild/_testmultiphase.vcxproj.filters
./PCbuild/_testimportmultiple.vcxproj
./PCbuild/_testclinic.vcxproj.filters
./PCbuild/_testbuffer.vcxproj.filters
./PCbuild/_testinternalcapi.vcxproj.filters
./PCbuild/_testinternalcapi.vcxproj
./PCbuild/_testsinglephase.vcxproj
./PCbuild/_testembed.vcxproj.filters
./PCbuild/_testclinic_limited.vcxproj.filters
./PCbuild/_testcapi.vcxproj.filters
./PCbuild/_testcapi.vcxproj
./PCbuild/_testclinic_limited.vcxproj
./Lib/test/_test_eintr.py
./Lib/test/_test_venv_multiprocessing.py
./Lib/test/test_unittest/_test_warnings.py
./Lib/test/_test_atexit.py
./Lib/test/test_zipfile/_path/_test_params.py
./Lib/test/_test_multiprocessing.py
./Lib/test/_test_embed_structseq.py
./Lib/test/_test_embed_set_config.py
./Modules/_testcapi
./Modules/_testcapi_feature_macros.inc
./Modules/_testimportmultiple.c
./Modules/_testinternalcapi
./Modules/_testmultiphase.c
./Modules/_testclinic_limited.c
./Modules/_testclinic.c
./Modules/clinic/_testclinic.c.h
./Modules/clinic/_testclinic_depr.c.h
./Modules/clinic/_testinternalcapi.c.h
./Modules/clinic/_testmultiphase.c.h
./Modules/clinic/_testclinic_limited.c.h
./Modules/_testcapimodule.c
./Modules/_testsinglephase.c
./Modules/_testinternalcapi.c
./Modules/_testbuffer.c
./PC/clinic/_testconsole.c.h
./PC/_testconsole.c
```

### Additional contract requirements

- When classifying changed file paths, files whose basename begins with `_test` must cause the pull request to receive the `tests` label.
