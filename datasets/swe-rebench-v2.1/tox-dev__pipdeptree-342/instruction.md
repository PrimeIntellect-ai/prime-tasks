duplicate packages when using `importlib.metadata`
Hmm, the thought of duplicate packages when using `importlib.metadata` came to my mind and it looks like the discovery algorithm will need more work. I installed `pytest` both in my system environment and in a temporary directory. I assigned this temporary directory to `PYTHONPATH` and was able to see it twice, including its dependencies. Here's an example:
```console
$ mkdir temp-site-pkgs
$ pip install --target temp-site-pkgs/ pytest
Collecting pytest
  Using cached pytest-8.1.1-py3-none-any.whl.metadata (7.6 kB)
. . .
Installing collected packages: tomli, pluggy, packaging, iniconfig, exceptiongroup, pytest
Successfully installed exceptiongroup-1.2.0 iniconfig-2.0.0 packaging-24.0 pluggy-1.4.0 pytest-8.1.1 tomli-2.0.1
$ PYTHONPATH=/workspaces/pipdeptree/temp-site-pkgs pipdeptree -a -d 0
attrs==23.2.0
Automat==22.10.0
cachetools==5.3.3
certifi==2024.2.2
cffi==1.16.0
cfgv==3.4.0
chardet==5.2.0
charset-normalizer==3.3.2
colorama==0.4.6
constantly==23.10.4
covdefaults==2.3.0
coverage==7.4.4
cryptography==42.0.5
cssselect==1.2.0
diff_cover==8.0.3
distlib==0.3.8
exceptiongroup==1.2.0                             # <--- Here
exceptiongroup==1.2.0
filelock==3.13.1
gitdb==4.0.11
GitPython==3.1.41
hyperlink==21.0.0
identify==2.5.35
idna==3.6
incremental==22.10.0
iniconfig==2.0.0                             # <--- Here
iniconfig==2.0.0
itemadapter==0.8.0
itemloaders==1.1.0
Jinja2==3.1.3
jmespath==1.0.1
lxml==5.2.1
MarkupSafe==2.1.5
nodeenv==1.8.0
packaging==24.0                         # <--- Here
packaging==24.0
parsel==1.9.0
pip==24.0
pip==23.0.1
pipdeptree==2.16.3.dev3+g91d21e3
platformdirs==4.2.0
pluggy==1.4.0                                # <--- Here
pluggy==1.4.0
pre-commit==3.7.0
Protego==0.3.0
pyasn1==0.6.0
pyasn1_modules==0.4.0
pycparser==2.22
PyDispatcher==2.0.7
Pygments==2.17.2
pyOpenSSL==24.1.0
pyproject-api==1.6.1
pytest==8.1.1                             # <--- Here
pytest==8.1.1
pytest-cov==4.1.0
pytest-mock==3.14.0
PyYAML==6.0.1
queuelib==1.6.2
requests==2.31.0
requests-file==2.0.0
Scrapy==2.11.1
service-identity==24.1.0
setuptools==69.0.3
six==1.16.0
smmap==5.0.1
tldextract==5.1.2
tomli==2.0.1                             # <--- Here
tomli==2.0.1
tox==4.14.2
Twisted==24.3.0
typing_extensions==4.10.0
urllib3==2.2.1
virtualenv==20.25.1
w3lib==2.1.2
wheel==0.42.0
zope.interface==6.2
```

_Originally posted by @kemzeb in https://github.com/tox-dev/pipdeptree/pull/333#issuecomment-2035034418_

### Additional contract requirements

When package metadata for the same package is discovered in multiple locations, pipdeptree should list the package only once and should not repeat its dependency listing.
