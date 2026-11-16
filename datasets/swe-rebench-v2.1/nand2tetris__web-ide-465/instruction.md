[bug]: VMEmulator is running with duplicated labels
### Tool

None

### Interface

None

### Contact Details

_No response_

### What happened?

If we are compiling 2+ jack files with at least 1 label in each, in VM code we will have L0 label duplicated. Is this expected? Seem like it shouldn't run at all.
Why am I asking? I am trying to use vm translator for compiled files and I get duplicated label exception. Probably I will need to provide a hotfix for this one. [HIDDEN]

### Additional Comments

_No response_

### Do you want to try to fix this bug?

- [ ] I want to try to add this feature!

### Code of Conduct

- [X] I agree to follow this project's Code of Conduct

### Additional contract requirements

- When code from several Jack files is compiled together, the generated VM code must not define the same label more than once across those files, so that the combined VM program can be loaded and run without duplicate-label errors.
