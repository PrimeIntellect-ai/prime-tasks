{{else if foo}} is not handled correctly
```handlebars
{{#if isMorning}}
  Good morning
{{else if isAfternoon}}
  Good afternoon
{{else}}
  Good night
{{/if}}
```
Will report:

```
Incorrect indentation for `if` beginning at ('rwe/components/criteria-operator-select/template.hbs'@ L3:C0).
Expected `{{/if}}` ending at ('rwe/components/criteria-operator-select/template.hbs'@ L7:C0)to be at an indentation of 0 but was found at -7.
```
