How do I tell if submit was attempted but validation failed
The behaviour I'm trying to produce is to have the "submit" button enabled, even if all the fields are invalid.  Once the user clicks submit, I want to disable the button if there are validation errors.  That way I can hide all error messages until `touched`, but if the user clicks submit, all the errors show up.

I tried `submitFailed` but that doesn't seem to be set to `true` unless the form is valid when handleSubmit is called.
