feat(bloc_lint): support for // ignore
**Description**
bloc_lint does not take `// ignore` into account

**Expected Behavior**
Don't trigger linter

**Screenshots**
<img width="870" alt="Image" src="https://github.com/user-attachments/assets/084bcbc1-1c41-4fde-a22e-b272ca221919" />

![Image](https://github.com/user-attachments/assets/ff991767-9372-4e4c-b590-fbb26c930452)

### Additional contract requirements

A `// ignore:` directive suppresses a diagnostic only when the diagnostic's lint rule is named in the directive. Diagnostics from other lint rules on the affected code line remain reportable.
