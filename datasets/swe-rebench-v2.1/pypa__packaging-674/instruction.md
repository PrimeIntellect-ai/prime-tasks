Specifiers with `.*` and epoch changed behaviours
Hello, it seems that `SpecifierSet.contains` works differently between versions 21 and 23, when the `==` operator is used with a version that contains both an epoch and `.*`:

```bash
> docker run --rm -it python:3.11 /bin/bash

python3 -m venv /tmp/venv21

/tmp/venv21/bin/python3 -m pip install 'packaging==21.3'

cat <<EOF | /tmp/venv21/bin/python3 -
from packaging.requirements import Requirement

req = Requirement('metomi-isodatetime==1!3.0.*')

print(f"{req.specifier.contains('1!3.0.0', prereleases=True)=}")
EOF
# => req.specifier.contains('1!3.0.0', prereleases=True)=True

# ---

python3 -m venv /tmp/venv23

/tmp/venv23/bin/python3 -m pip install 'packaging==23.0'

cat <<EOF | /tmp/venv23/bin/python3 -
from packaging.requirements import Requirement

req = Requirement('metomi-isodatetime==1!3.0.*')

print(f"{req.specifier.contains('1!3.0.0', prereleases=True)=}")
EOF
# => req.specifier.contains('1!3.0.0', prereleases=True)=False
```

Is this change intended?

I went quickly trough PEP 440 and PEP 508 and I have the impression that this kind of requirement/comparison is allowed, but I might be wrong or missing something.

---

Note that when we remove the version epoch, the return value of `contains` is the same for both 21.3 and 23:

```bash
cat <<EOF | /tmp/venv21/bin/python3 -
from packaging.requirements import Requirement

req = Requirement('metomi-isodatetime==3.0.*')

print(f"{req.specifier.contains('3.0.0', prereleases=True)=}")
EOF
# => req.specifier.contains('3.0.0', prereleases=True)=True

cat <<EOF | /tmp/venv23/bin/python3 -
from packaging.requirements import Requirement

req = Requirement('metomi-isodatetime==3.0.*')

print(f"{req.specifier.contains('3.0.0', prereleases=True)=}")
EOF
# => req.specifier.contains('3.0.0', prereleases=True)=True
```

(Obs: related to https://github.com/pypa/setuptools/issues/3802)

### Additional contract requirements

- For the specifier `==2!1.0.*`, `Specifier.contains("2!1.0.0")` must return `True`.
