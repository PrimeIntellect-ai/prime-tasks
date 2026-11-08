The template's `in` doesn't work when a slash (/) exists due to escaping
Given the Rust + template

```
context.insert("friends", &vec!["https://Bob", "Kate"]);
...
Output: {% if "https://Bob" in friends %}TRUE{% endif %}
```

the output will be blank.

If we instead run:

- `{% if "https://Bob" in ["https://Bob", "Kate"] %}`
- `{% if "https://Bob"|safe in friends %}TRUE{% endif %}`

then the statement works as expected.

---

After [adding a test to ensure I wasn't mad](https://github.com/Smerity/tera/commit/2ccb8785f18cb55d82f0fdc7bf5ab66ec00583b0) [HIDDEN] [HIDDEN] Thus, to run the above correctly we need to instead run:

```
context.insert("friends", &vec!["https://Bob", "Kate"]);
...
Output: {% if "https://Bob"|safe in friends %}TRUE{% endif %}
```

[HIDDEN]

**If this is expected behaviour:** I'll add a section to the [containing docs](https://tera.netlify.app/docs/#containing)

**If it isn't expected behaviour:** I can investigate this issue further (though would appreciate someone with more Tera knowledge as I'm uncertain how problematic [HIDDEN] might be)

### Additional contract requirements

- The `in` operator must report a slash-containing string as present when the same string is an element of a collection supplied through context. This must work without applying `|safe`.
