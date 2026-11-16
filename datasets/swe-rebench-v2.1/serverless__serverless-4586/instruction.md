Add a correct keyword suggestion feature when typo
<!--
1. If you have a question and not a bug/feature request please ask it at http://forum.serverless.com
2. Please check if an issue already exists so there are no duplicates
3. Check out and follow our Guidelines: https://github.com/serverless/serverless/blob/master/CONTRIBUTING.md
4. Fill out the whole template so we have a good overview on the issue
5. Do not remove any section of the template. If something is not applicable leave it empty but leave it in the Issue
6. Please follow the template, otherwise we'll have to ask you to update it
-->

# This is a Feature Proposal

## Description
For feature proposals:
* What is the use case that should be solved. The more detail you describe this in the easier it is to understand for us.

If users make a typo when typing any commands, It would be great if there is a feature which provides supposably a correct keyword suggestion something like this: (would be trigged by hitting enter key)
```
$ serverless deploi
Do you mean "deploy"?
```

I have seen the feature when using other command line tools. I think if that would be introduced to the framework, it would be great and being more helpfully for users.

However, I don't have a detailed plan how to work on this and what libraries to introduce so far.
If introducing, we need to decide these stuff at first.

* If there is additional config how would it look
Turn on it as a default

### Additional contract requirements

- The suggestion feature is enabled by default; no configuration is required.
- When the CLI cannot find the command a user entered, the error it raises must include the suggestion returned by `getCommandSuggestion`, formatted as:

  `Serverless command "<input>" not found. Did you mean "<suggestion>"? Run "serverless help" for a list of all available commands.`

  where `<input>` is the mistyped command and `<suggestion>` is the suggested command name.
