AllocatedStorage can't be a Ref
If I try to use a Parameter for setting the AllocatedStorage of an RDS database I get the following error:
```
  File "/home/cup/.local/share/virtualenvs/system-oD26KLrH/lib/python3.11/site-packages/troposphere/validators/rds.py", line 402, in validate_dbinstance
    and int(allocated_storage) < 400
        ^^^^^^^^^^^^^^^^^^^^^^
TypeError: int() argument must be a string, a bytes-like object or a real number, not 'Ref'
```

Version: 4.4.1
