taskcat test run --keep-failed -> ValueError status is not a valid property of <class 'taskcat._cfn.stack.Stack'>
**Describe the bug**
Ran `taskcat test run --keep-failed` across (21) AWS Commercial Regions.  It did not delete ANY of the CloudFormation Stacks (both successful & failed).

- After `reporting on` messages come out, see below messages:
  - `[INFO   ] : deleting successful stacks`
  - `[ERROR  ] : ValueError status is not a valid property of <class 'taskcat._cfn.stack.Stack'>`

**To Reproduce**
Steps to reproduce the behavior:
1. Are you testing a *QuickStart* or *Custom template*? `No`
2. Attach or link a copy of the template if possible (**remove any sensitive info**)
3. Provide the parameters that you passed. (**remove any sensitive info**)
4. How did you install taskcat? (docker or pip3) `pipx`
5. Are you using a *profile*, *an instance role* or  *access keys* to run taskcat? `profile`
6. Is your AWS environment configured via `aws configure`? `yes`

**Expected behavior**
- I was expecting that it would delete the stacks in all AWS regions where stack deployed successfully, and that it would not delete the stacks in the AWS regions where stack deployment failed.
- FYI, it works properly when I do `taskcat test run`, and then stacks are deleted in all AWS regions (both successful & failed stacks)

**Version (Please make sure you are running the latest version of taskcat)
 - Taskcat Version: `0.9.23`
 - Python3 Version: `3.8.7`
