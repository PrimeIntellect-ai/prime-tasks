`ollama create` not working
Following the `Modelfile` tutorial in the readme, I can't get `ollama create` to work.

My modelfile is as follows:
```
FROM codellama:13b-instruct

SYSTEM """
You are Mario from super mario bros, acting as an assistant.
"""
```

When I attempt to create from the modelfile, I get the following error:

```
transferring model data
pulling model
pulling manifest
Error: pull model manifest: file does not exist
```

I have pulled the `codellama:13b-instruct` model to my machine and succesfully run it.

I'm using a M2 Macbook running ollama `0.1.13`

### Additional contract requirements

- When the base model named by a Modelfile `FROM` command is already available locally, `ollama create` must use it without failing to fetch a nonexistent remote manifest.
- Leading or trailing whitespace around the model reference in a Modelfile `FROM` command must not change which model is identified.
