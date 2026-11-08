Request: remove merging of explicit configurations with atom-prettier settings
I just spent some time looking into why my prettier settings in package.json weren't being respected, and it's due to [them being assigned over atom-prettier settings](https://github.com/prettier/prettier-atom/blob/master/src/executePrettier/buildPrettierOptions.js#L70-L74).  I'm wondering what the use-case is for

1. allowing users to `only format if a prettier config is found` and
2. assigning the prettier config over those in atom-prettier.

i.e. why would I want to require an explicit configuration while also using the one local to my editor?  I assume the use-case for allowing users to require both an explicit prettier instance and settings would be to ensure consistent formatting should they move to a different editor or machine.

Even if I set atom-prettier's settings to the defaults, this could become problematic should the defaults in the local prettier instance be different.

Another less breaking solution would be to add an option to ignore atom-prettier's configuration settings.

I'm willing to create a PR if either solution is agreeable.
