sls offline cleanup fails if folder does not exist
<!--
1. Please check if an issue already exists. This bug may have already been documented
2. Check out and follow our Guidelines: https://github.com/serverless/serverless-azure-functions/CONTRIBUTING.md
3. Fill out the whole template so we have a good overview on the issue
4. Do not remove any section of the template. If something is not applicable leave it empty but leave it in the Issue
5. Please follow the template, otherwise we'll have to ask you to update it
-->

# sls offline cleanup fails if folder does not exist

## Description

- What went wrong?

When running sls offline cleanup the command throw an exception if any function folder does not exist within the filesystem.

- What did you expect should have happened?

If any folder doesn't exist it should be skipped and continue onto the next folder

- What was the config you used? N/A
- What stacktrace or error message from your provider did you see? N/A

Similar or dependent issues:

- N/A

## Additional Data

- **_Serverless Framework Version you're using_**: 1.5.2
- **_Serverless CLI Version you're using_**: 1.5.2
- **_Serverless Azure Plugin Version you're using_**: 1.0.0
- **_Operating System_**:
- **_Stack Trace_**:
- **_Provider Error messages_**:
