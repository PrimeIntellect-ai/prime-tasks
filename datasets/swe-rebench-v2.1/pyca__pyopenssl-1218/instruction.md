23.1.1: pytest warnings
<details>

```console
+ /usr/bin/python3 -Bm pytest -ra
=========================================================================== test session starts ============================================================================
platform linux -- Python 3.8.9, pytest-6.2.4, py-1.10.0, pluggy-0.13.1
OpenSSL: b'OpenSSL 1.1.1k  FIPS 25 Mar 2021'
cryptography: 3.3.1
rootdir: /home/tkloczko/rpmbuild/BUILD/pyopenssl-20.0.1, configfile: setup.cfg, testpaths: tests
plugins: forked-1.3.0, shutil-1.7.0, virtualenv-1.7.0, expect-1.1.0, httpbin-1.0.0, xdist-2.2.1, flake8-1.0.7, timeout-1.4.2, betamax-0.8.1, pyfakefs-4.4.0, freezegun-0.4.2, cases-3.4.6, case-1.5.3, isort-1.3.0, aspectlib-1.5.2, asyncio-0.15.1, toolbox-0.5, xprocess-0.17.1, flaky-3.7.0, aiohttp-0.3.0, checkdocs-2.7.0, mock-3.6.1, rerunfailures-9.1.1, requests-mock-1.9.3, hypothesis-6.13.7, Faker-8.4.0, cov-2.12.1
collected 525 items

tests/test_crypto.py ............................................................................................................................................... [ 27%]
................................................................................................................................................                     [ 54%]
tests/test_debug.py .                                                                                                                                                [ 54%]
tests/test_rand.py ....                                                                                                                                              [ 55%]
tests/test_ssl.py .................................................................................................................................................. [ 83%]
.......................s..............s...............................................                                                                               [ 99%]
tests/test_util.py .                                                                                                                                                 [100%]

============================================================================= warnings summary =============================================================================
../../../../../usr/lib/python3.8/site-packages/_pytest/config/__init__.py:1233
  /usr/lib/python3.8/site-packages/_pytest/config/__init__.py:1233: PytestConfigWarning: Unknown config option: strict

    self._warn_or_fail_if_strict(f"Unknown config option: {key}\n")

tests/test_crypto.py:39
  /home/tkloczko/rpmbuild/BUILD/pyopenssl-20.0.1/tests/test_crypto.py:39: DeprecationWarning: PKCS#7 support in pyOpenSSL is deprecated. You should use the APIs in cryptography.
    from OpenSSL.crypto import PKCS7, load_pkcs7_data

tests/test_crypto.py:40
  /home/tkloczko/rpmbuild/BUILD/pyopenssl-20.0.1/tests/test_crypto.py:40: DeprecationWarning: PKCS#12 support in pyOpenSSL is deprecated. You should use the APIs in cryptography.
    from OpenSSL.crypto import PKCS12, load_pkcs12

tests/test_ssl.py::TestContext::test_set_cipher_list[hello world:AES128-SHA1]
  /home/tkloczko/rpmbuild/BUILD/pyopenssl-20.0.1/tests/test_ssl.py:493: DeprecationWarning: str for cipher_list is no longer accepted, use bytes
    context.set_cipher_list(cipher_string)

tests/test_ssl.py::TestConnection::test_client_set_session
  /home/tkloczko/rpmbuild/BUILD/pyopenssl-20.0.1/tests/test_ssl.py:2637: DeprecationWarning: str for buf is no longer accepted, use bytes
    ctx.set_session_id("unity-test")

-- Docs: https://docs.pytest.org/en/stable/warnings.html
===Flaky Test Report===

test_gmtime_adj_notBefore passed 1 out of the required 1 times. Success!
test_gmtime_adj_notAfter passed 1 out of the required 1 times. Success!
test_set_cipher_list_no_cipher_match passed 1 out of the required 1 times. Success!

===End Flaky Test Report===
========================================================================= short test summary info ==========================================================================
SKIPPED [1] tests/test_ssl.py:3021: Python 2 only
SKIPPED [1] tests/test_ssl.py:3228: Python 2 only
=============================================================== 523 passed, 2 skipped, 5 warnings in 11.36s ================================================================
```
</details>

### Additional contract requirements

Running pytest with the project configuration must not report that `strict` is an unknown configuration option.
