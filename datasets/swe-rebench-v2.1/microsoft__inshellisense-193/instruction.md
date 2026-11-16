Provide intenllisense for possible arguments.
**Maybe it should be able to do something like**
e.g. list all local branches when I type "git checkout" in bash in a repository folder

### Additional contract requirements

- In the terminal, after entering `dotnet add package Holoon.Newtonsoft`, the suggestion display must contain `CanBeUndefi…│`.
- Filepath suggestions must have priority `55`.
- Typing the partial argument `dotnet add package Microsoft.Azure.WebJo` must suggest `Microsoft.Azure.WebJobs`.
