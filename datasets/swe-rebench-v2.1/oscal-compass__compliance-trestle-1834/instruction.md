get_control_response missing "This System" component
## Describe the bug

For controls with statements, the "This System" implementation statements are missing from the individual parts.

This appears to be a [regression introduced](https://github.com/oscal-compass/compliance-trestle/pull/1358/files?diff=unified&w=0#diff-0543d4fc8151f036968d940bbe821cd67cb5640cacd78fb22f8709439247f4c6L262-L264) in #1358

## To Reproduce

Steps to reproduce the behavior:

1. Create a system security plan with a control with multiple parts (such as SC-7)
1. Use `trestle author jinja` in combination with `ssp_md_writer.get_control_response` to create a markdown SSPP
1. See that the implementation statements for each individual part are missing for the `This System` component (though they'll be present for any other components)

## Expected behavior

I expected that `This System` implementation statements are included for all parts of the control.

## Screenshots / Logs.

If applicable, add screenshots to help explain your problem.

## Environment

- OS: \[e.g. iOS\] Docker/Debian
- Python version: 3.11.11
- Installed packages: compliance-trestle 3.8.0
