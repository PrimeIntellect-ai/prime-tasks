Broader of  dropdown box misplaced when the line contains chinese characters
**Describe the bug**
Broader of dropdown box misplaced when the line contains chinese characters
![截图 2024-03-18 19-14-50](https://github.com/microsoft/inshellisense/assets/88639622/16e44e29-7997-4ab5-acce-5f4875288206)

**To Reproduce**
Steps to reproduce the behavior:
1. Go to a folder whose subfolders' names contain chinese characters
2. Run commend `cd`
3. See error

**Expected behavior**
Broader of dropdown box placed in where it should be

**Environment**
 - OS: Debian 12
 - Output of `is --version`: 0.0.1-rc.9
 - Nodejs Version: v18.19.0
 - Shell: bash
 - Shell Version: 5.2.15

**Additional context**
N/A

### Additional contract requirements

When the command line contains wide characters (such as Chinese characters), the suggestion dropdown box must still be drawn with aligned borders: every rendered row of the box, including the top and bottom border rows, must have the same display width, so the box is placed where it should be.
