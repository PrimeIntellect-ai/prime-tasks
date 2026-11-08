[BUG] requirements needed with outputs
Conda forge fails with the message `'PYTHON' is undefined` when the `outputs` section is defined (i.e. extra requires).

The reason is this

```yaml
outputs:
  - name: pypushflow
    requirements:
      host: &id001
        - python >=3.6
        - pip
      run:
        - python >=3.6
  - name: pypushflow-mx
    requirements:
      host: *id001
      run:
        - pypushflow =={{ version }}
        - pymongo >=4
```

which should become

```yaml
requirements: # !!!!
  host:
    - python >=3.6
    - pip

outputs:
  - name: pypushflow
    requirements:
      host:
        - python >=3.6
        - pip
      run:
        - python >=3.6
  - name: pypushflow-mx
    requirements:
      host:
        - python >=3.6
        - pip
      run:
        - python >=3.6  # !!!!!
        - pypushflow =={{ version }}
        - pymongo >=4
```

Command:

```
grayskull pypi pypushflow --extras-require-all --extras-require-split --extras-require-test test --extras-require-exclude dev --strict-conda-forge
```

### Additional contract requirements

When the recipe defines an `outputs` section (i.e. split extra requirements):

- The top-level `requirements` mapping must include the host requirements (the same `host` list used for the package), and its `run` list must be empty.
- Every entry in `outputs` must include the host requirements under `requirements.host`.
- Every split output's `requirements.run` must include the Python runtime requirement (the `python ...` entry) in addition to the package pin and the extra's own requirements.
