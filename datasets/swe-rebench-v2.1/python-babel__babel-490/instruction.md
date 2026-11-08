"ValueError: expected only letters, got u'ko-kr'"
With Babel 2.4.0 we get:
 File "/home/jenkins/workspace/openstack-manuals-tox-doc-publishlang/.tox/venv/local/lib/python2.7/site-packages/babel/core.py", line 1093, in parse_locale
"ValueError: expected only letters, got u'ko-kr'"

This comes from using "ko-kr" as locale in  http://git.openstack.org/cgit/openstack/openstack-manuals/tree/doc/install-guide/source/locale/ko_KR/LC_MESSAGES/install-guide.po#n42

We didn't have this problem with earlier Babel releases.

Other places in Babel accept the '-' like https://github.com/python-babel/babel/blob/v2.4.0/tests/test_core.py#L100 - why not here as well and break existing files this way?
