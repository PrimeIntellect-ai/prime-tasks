Cannot upload project avatar: 'avatar is invalid'
[Our project calls `uploadAvatar()`](https://github.com/acquia/cli/blob/fae9193756f42a2b873b573327a6747067e96b66/src/Command/CodeStudio/CodeStudioCommandTrait.php#L253) after creating a GitLab project. I'm pretty sure this has worked in the past, but recently stopped working, throwing an `avatar is invalid` exception: https://github.com/acquia/cli/issues/1377

I did some debugging and it looks like a problem with this library. A curl request with the same avatar to the same API endpoint works fine:

`curl --location --request PUT 'https://code.acquia.com/api/v4/projects/1092' --header 'Authorization: Bearer [snip]' --form 'avatar=@drupal_icon.png'`

I suspect GitLab changed something in the expected file or PUT format that's breaking this call.
