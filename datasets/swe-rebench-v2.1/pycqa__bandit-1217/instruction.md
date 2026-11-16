Bandit version 1.8.1 showing false-positives in B106 warnings
### Describe the bug

Openstack Neutron (and other Openstack projects) use bandit to check our python files for possible security issues.

Today, right after version 1.8.1 dropped, it started breaking our gate. Here's a copy/paste of one of the snippets:

```
>> Issue: [B106:hardcoded_password_funcarg] Possible hardcoded password: 'True'
   Severity: Low   Confidence: Medium
   CWE: CWE-259 (https://cwe.mitre.org/data/definitions/259.html)
   More Info: https://bandit.readthedocs.io/en/1.8.1/plugins/b106_hardcoded_password_funcarg.html
   Location: neutron/conf/agent/metadata/config.py:56:4
54	                default=8775,
55	                help=_("TCP Port used by Nova metadata server.")),
56	    cfg.StrOpt('metadata_proxy_shared_secret',
57	               default='',
58	               help=_('When proxying metadata requests, Neutron signs the '
59	                      'Instance-ID header with a shared secret to prevent '
60	                      'spoofing. You may select any string for a secret, '
61	                      'but it must match here and in the configuration used '
62	                      'by the Nova metadata server. NOTE: Nova uses the same '
63	                      'config key, but in [neutron] section.'),
64	               secret=True),
65	    cfg.StrOpt('nova_metadata_protocol',
66	               default='http',
```

The 'secret=True' isn't a password at all. The entire file is at:

https://github.com/openstack/neutron/blob/master/neutron/conf/agent/metadata/config.py#L56

There were other places with this same signature failing as well.

We can work around it by either ignoring B106 or pinning to 1.8.0 but would be good to get it fixed.

Please let me know if there is anything else needed to help track this down.

Oh, and the url that gets printed there is a 404, don't know if that is temporary.

### Reproduction steps

```bash
Run bandit against the file I linked.
```

### Expected behavior

Should not see any failure.

### Bandit version

1.8.0 (Default)

### Python version

3.13 (Default)

### Additional context

_No response_

### Additional contract requirements

The false positive is produced by the B106 check (`hardcoded_password_funcarg`).
That check must only report a hardcoded password when the keyword argument's
value is a string literal. In particular:

- A call such as
  `cfg.StrOpt('metadata_proxy_shared_secret', default='', help='...', secret=True)`
  must not produce a B106 finding, because the value passed to `secret` is the
  boolean literal `True` and not a string. The same applies to any other keyword
  argument whose name matches the password-like candidate list (`password`,
  `pass`, `passwd`, `pwd`, `secret`, `token`, `secrete`) but whose value is not a
  string literal.
- A call such as `doLogin(password='blerg')` must still produce a B106 finding,
  because the value passed to `password` is a string literal.
