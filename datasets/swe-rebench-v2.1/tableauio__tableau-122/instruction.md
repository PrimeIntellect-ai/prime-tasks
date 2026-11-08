protogen(yaml): only read schema documents for templating data document
Design goal: support Jinja2 (or other templating libs) templating of data document
```yaml
---
"@sheet": "@TABLEAU"
ServiceConf:
  Template: true
---
# define schema
"@sheet": "@ServiceConf"
ID: uint32
Name: string
---
"@sheet": ServiceConf
ID: {{ env.id }}
Name: {{ env.name}}
{% if env.name == 'prod' %}
Enabled: true
{% else %}
Enabled: false
{% endif %}
```
