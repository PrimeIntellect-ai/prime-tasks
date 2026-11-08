Remove reliance on settings block
API breaks if a collection schema doesn't include a `settings` block. We should be able to function without it and just use the default values for everything.
