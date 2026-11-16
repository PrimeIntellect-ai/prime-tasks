terraform_docs runtime failure  "panic: runtime error: invalid memory address or nil pointer dereference"
<!-- Please note, this template is for bugs report, not feature requests -->
<!-- For more information, see the Contributing Guidelines at -->
<!-- https://github.com/terraform-docs/terraform-docs/tree/master/CONTRIBUTING.md -->

**Describe the bug**

terraform_docs runtime failure  "panic: runtime error: invalid memory address or nil pointer dereference".
running via precommit hooks. its being invoked from microsoft azure devops pipeline.

Starting: Run pre-commit-terraform on /home/vsts/work/1/s/terraform/hhck-webapp
==============================================================================
Task         : Command line
Description  : Run a command line script using Bash on Linux and macOS and cmd.exe on Windows
Version      : 2.164.2
Author       : Microsoft Corporation
Help         : https://docs.microsoft.com/azure/devops/pipelines/tasks/utility/command-line
==============================================================================
Generating script.
========================== Starting Command Output ===========================
/bin/bash --noprofile --norc /home/vsts/work/_temp/158cd010-1a06-4dea-a6d6-50c0f7ed0314.sh
pre-commit run --files *
[INFO] Initializing environment for git://github.com/antonbabenko/pre-commit-terraform.
Terraform docs...........................................................Failed
hookid: terraform_docs

panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x18 pc=0x7de744]

goroutine 1 [running]:
github.com/terraform-docs/terraform-docs/internal/cli.(*cfgreader).exist(0xc0000b41c0, 0xc0000b41c0, 0x2, 0xc00001cf40)
	/home/runner/work/terraform-docs/terraform-docs/internal/cli/reader.go:22 +0xe4
github.com/terraform-docs/terraform-docs/internal/cli.PreRunEFunc.func1(0xc00008fb80, 0xc000112240, 0x1, 0x1, 0x0, 0x0)
	/home/runner/work/terraform-docs/terraform-docs/internal/cli/run.go:46 +0x1b9
github.com/spf13/cobra.(*Command).execute(0xc00008fb80, 0xc000112220, 0x1, 0x1, 0xc00008fb80, 0xc000112220)

**To Reproduce**

Steps to reproduce the behavior:

1. download curl -Lo ./terraform-docs https://github.com/terraform-docs/terraform-docs/releases/download/v0.10.0-rc.1/terraform-docs-v0.10.0-rc.1-$(uname | tr '[:upper:]' '[:lower:]')-amd64
2. configure terraform_docs from precommit
3. execute precommit.


**Expected behavior**

terraform_docs should run successfully and return passed status without throwing runtime errors.
**Version information:**

- terraform-docs version (use `terraform-docs --version`): **v0.10.0-rc.1**
- Go version (if you manually built. use `go version`): **1.14.4**
- OS (e.g. Windows, MacOS): **Ubuntu**


Thanks in advance

Cheers
Omkar
