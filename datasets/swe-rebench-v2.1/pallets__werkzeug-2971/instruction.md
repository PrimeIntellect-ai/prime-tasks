increase pbkdf2 iterations
This needs to be bumped regularly to account for faster computers. Django now sets it to 1,000,000: https://github.com/django/django/commit/04a208d7f19f393ad92ba7cef31842318be2d38a.
