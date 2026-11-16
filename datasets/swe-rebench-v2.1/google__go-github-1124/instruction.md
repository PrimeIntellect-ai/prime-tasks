Add ability to create signed commits.
This just involves populating an extra field on commit creation: `signature` with a armor detached GPG signature, as described in the docs: https://developer.github.com/v3/git/commits/#create-a-commit
