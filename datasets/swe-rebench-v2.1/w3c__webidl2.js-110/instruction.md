Extended Attributes `rhs` should always be there
It's somewhat annoying to have to check for missing properties, as is the case for `rhs` on extended attributes.

We should make sure we don't conditionally add/remove members - and where they are null, they should just be `null`.
