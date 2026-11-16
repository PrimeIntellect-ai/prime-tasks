Apply custom error processor for generic HTTP errors even `json_errors` is `False`
Currently, if the `json_errors` is `False` when creating the app instance, the error processor registered with `app.error_processor` will not be applied on generic HTTP errors. I think it's better to change this behavior to match the behavior of `auth.error_processor` and keep it explicit.
