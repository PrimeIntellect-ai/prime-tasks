max property is being removed for every type input
# Bug Report

<!-- First, thank you for reporting a bug. That takes time and we appreciate that! -->

| Subject        | Details                                                         |
| :------------- | :---------------------------------------------------------------|
| Rector version | v0.17.0             |

<!-- Please describe your problem here. -->

## Minimal PHP Code Causing Issue

```
'config' => [
    'type' => 'input',
    'max' => 255,
],
```

## Expected Behaviour

Normal input fields should be allowed to define a max property, right?
I think "MigrateToEmailTypeRector" is used for this, and it shouldn't.
