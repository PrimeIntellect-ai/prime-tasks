`SelectionPrompt` does not search on results of `UseConverter`
**Information**
 - OS: MacOS (also tested on Windows)
 - Version: 0.49.1
 - Terminal: IntelliJ Rider Built-in Terminal (using Bash)

**Describe the bug**
Selection prompts which use `UseConverter` do not jump to the search (they do not use the mapped text as the search index).

**To Reproduce**
- Create a selection prompt
- Use .UseConverter()
- Search
- Observe that the result you have searched for is not jumped to

You can also search for the underlying object and observe that it is jumped to.

Example unit test that currently fails (where `MyClass` is just a class with a name parameter):
```c#
    [Fact]
    public void Should_Search_In_Remapped_Result()
    {

        // Given
        var console = new TestConsole();
        console.Profile.Capabilities.Interactive = true;
        console.EmitAnsiSequences();
        console.Input.PushText("2");
        console.Input.PushKey(ConsoleKey.Enter);
        var myObject = new List<MyClass>{ new() { name = "Item 1" }, new() {name = "Item 2"} };

        // When
        var prompt = new SelectionPrompt<MyClass>()
            .Title("Select one")
            .EnableSearch()
            .UseConverter(o => o.name)
            .AddChoices(myObject);
        var selection = prompt.Show(console);

        // Then
        selection.name.ShouldBe("Item 2");
    }
```


**Expected behavior**
SelectionPrompt should search based on the results of `UseConverter` and not on the underlying object remapped by it. (see test)

**Screenshots**
If applicable, add screenshots to help explain your problem.


**Additional context**
Add any other context about the problem here.

---
Please upvote :+1: this issue if you are interested in it.
