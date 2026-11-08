ICU arguments mismatch warning
The code in https://github.com/ember-intl/ember-intl/pull/1285 works great! We've gotten rid of 50 or so ICU mismatch warnings.

However, there is still one around:

> [ember-intl] "activemodel.errors.template.header" ICU argument mismatch: "de": "model"

That can be reproduced using these two YAML files:

```yml
# de.yml
header: >
  {count, plural,
    one {Ein Fehler hat die Speicherung von {model} verhindert}
    other {# Fehler hat verhindert, dass {model} gespeichert wurden}
  }

# en.yml
header: >
  {count, plural,
    one {An error}
    other {# errors}
  } prevented this {model} from being saved

```


***

### Environment

- Ember Version: 3.17.0
- Ember CLI Version: 3.17.0
- Ember Intl Version: 5.0.7
- Browser(s): Chrome 80.0.3987.163
- Node Version: 10.18.1
- OS: macOS Catalina
