invalid-interactive additionalInteractiveTags not working?
I have this:

```<form {{action 'foo' on="submit"}}>```

and its failing the invalid-interactive check.  We don't have buttons in the form, but we want to be able to submit the form with the enter key for accessibility.  It seems like it should be okay for forms to submit actions...

I still think its odd to default forms to fail this check.  I'm trying to change this behavior with this rule and it doesn't seem to be working:

        'invalid-interactive': {additionalInteractiveTags:['form']},

when looking at 'lint-invalid-interactive.js' it doesn't appear to be using additionalInteractiveTags like 'lint-nested-interactive.js' is...
