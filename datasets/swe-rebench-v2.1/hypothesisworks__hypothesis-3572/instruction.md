Explicit support for special-use domains.
Hypothesis’ [`emails()`](https://hypothesis.readthedocs.io/en/latest/data.html#hypothesis.strategies.emails) strategy generated an email address `0@a.arpa` which was rejected by the [email-validator](https://github.com/JoshData/python-email-validator) package:
```python
>>> import email_validator
>>> email_validator.validate_email('0@a.arpa')
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/.../.venv/lib/python3.9/site-packages/email_validator/__init__.py", line 319, in validate_email
    domain_part_info = validate_email_domain_part(parts[1], test_environment=test_environment, globally_deliverable=globally_deliverable)
  File "/.../.venv/lib/python3.9/site-packages/email_validator/__init__.py", line 580, in validate_email_domain_part
    raise EmailSyntaxError("The domain name %s is a special-use or reserved name that cannot be used with email." % domain_i18n)
email_validator.EmailSyntaxError: The domain name a.arpa is a special-use or reserved name that cannot be used with email.
```

The email-validator package defines “special-use or reserved names” [here](https://github.com/JoshData/python-email-validator/blob/364d2d189e28b334437dcdbf554a484d07977a9b/email_validator/__init__.py#L19-L82).

Now, Hypothesis builds email addresses using the internal [`domains()`](https://hypothesis.readthedocs.io/en/latest/data.html#hypothesis.provisional.domains) strategy:

https://github.com/HypothesisWorks/hypothesis/blob/48165d90f6afc1c0cd618ae0659f02a88b579f8b/hypothesis-python/src/hypothesis/strategies/_internal/core.py#L2029-L2031

which doesn’t have explicit support to filter out or use these special-use domain names.

I think adding an optional kwarg `allow_special_use=True` to the `emails()` strategy which then propagates to the [`DomainNameStrategy` class](https://github.com/HypothesisWorks/hypothesis/blob/48165d90f6afc1c0cd618ae0659f02a88b579f8b/hypothesis-python/src/hypothesis/provisional.py#L47-L128) would be useful. Happy to supply a PR?

### Additional contract requirements

- `emails()` accepts an optional keyword argument `domains`, a Hypothesis `SearchStrategy` that generates domain name strings. When it is supplied, every generated address uses a domain produced by that strategy.
- By default, `emails()` never generates an address whose domain ends with `.arpa`.
