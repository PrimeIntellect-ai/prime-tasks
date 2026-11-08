Consider unicode line characters to visualize the tree
This package has a nice way of displaying the tree that I think could be easier to follow than the current way `pipdeptree` works using `├──` style characters:

- https://github.com/wimglenn/johnnydep

```
name                                     summary
---------------------------------------  -------------------------------------------------
boto3                                    The AWS SDK for Python
├── botocore<1.11.0,>=1.10.77            Low-level, data-driven core of boto 3.
│   ├── docutils>=0.10                   Docutils -- Python Documentation Utilities
│   ├── jmespath<1.0.0,>=0.7.1           JSON Matching Expressions
│   └── python-dateutil<3.0.0,>=2.1      Extensions to the standard Python datetime module
│       └── six>=1.5                     Python 2 and 3 compatibility utilities
├── jmespath<1.0.0,>=0.7.1               JSON Matching Expressions
└── s3transfer<0.2.0,>=0.1.10            An Amazon S3 Transfer Manager
    └── botocore<2.0.0,>=1.3.0           Low-level, data-driven core of boto 3.
        ├── docutils>=0.10               Docutils -- Python Documentation Utilities
        ├── jmespath<1.0.0,>=0.7.1       JSON Matching Expressions
        └── python-dateutil<3.0.0,>=2.1  Extensions to the standard Python datetime module
            └── six>=1.5                 Python 2 and 3 compatibility utilities
```

### Additional contract requirements

- When `sys.stdout.encoding` is `utf-8`, render dependency branches using Unicode tree connectors such as `├──`, `└──`, and `│`. When it is `ascii`, use the ASCII-style layout, with `  - ` branch markers and spaces for guides and indentation.
