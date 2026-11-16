Alone bold line formatting is escaped with markdown document
<!-- Please note, this template is for bugs report, not feature requests -->
<!-- For more information, see the Contributing Guidelines at -->
<!-- https://github.com/terraform-docs/terraform-docs/tree/master/CONTRIBUTING.md -->

**Describe the bug**
Using the output markdown document, I have an issue with alone bold line formatting. The `*` character is always escaped during generation.

**To Reproduce**

Steps to reproduce the behavior:

1. Create a module with a main.tf
2. Put those lines in main.tf:
```
/**
* **Please, read this line before starting**
*/
```
3. Run `terraform-docs markdown . > README.md` in module folder
4. Content of README.md:
```markdown
\*\*Please, read this line before starting\*\*
```

**Expected behavior**

```markdown
**Please, read this line before starting**
```

**Version information:**

- terraform-docs version: 0.10.1
- OS: Ubuntu

### Additional contract requirements

- Generated Markdown must not escape asterisks, including in mixed or unmatched sequences. In particular, preserve these strings exactly:
```
* lorem * ipsum *dolor*consectetur* `adipi * scing *elit*sit*`
** lorem ** ipsum **dolor**consectetur** `adipi ** scing **elit**sit**`
*** lorem *** ipsum ***dolor***consectetur*** `adipi *** scing ***elit***sit***`
**lorem ipsum dolor consectetur adipi scing elit sit**
```
