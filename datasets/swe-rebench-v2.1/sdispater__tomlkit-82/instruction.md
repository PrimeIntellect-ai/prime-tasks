.get on class OutOfOrderTableProxy now always return None
I just updated to poetry 1.0.4 that uses tomlkit 0.5.10 and custom repository are not added anymore.

```
(Pdb++) local_config.get("source")
(Pdb++) local_config.get("name")
(Pdb++) local_config.get("name", "potatoes")
'potatoes'
(Pdb++) local_config["name"]
'test'
(Pdb++) local_config["source"]
<AoT [{'name': 'testrepo', 'url': 'https://test-repo-url'}]>
```

I'm pretty sure it is related to that change: https://github.com/sdispater/tomlkit/pull/79

OS: ArchLinux
Python: 3.7, 3.8

Reproduced in docker as well with images python:3.7.x and python:3.8.x
