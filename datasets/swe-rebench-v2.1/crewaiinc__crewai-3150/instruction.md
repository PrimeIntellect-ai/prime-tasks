[BUG] Parameter `create_directory` at `Task` class does't exists.
### Description

Parameter `create_directory` at `Task` class doesn't exist.

### Steps to Reproduce

[Parameter `create_directory` at `Task` class does't exists.](https://docs.crewai.com/en/concepts/tasks#creating-directories-when-saving-files)

Reproduce code above.

### Expected behavior

Task would run and directories would be created.

### Screenshots/Code snippets

```
# ...

save_output_task = Task(
    description='Save the summarized AI news to a file',
    expected_output='File saved successfully',
    agent=research_agent,
    tools=[file_save_tool],
    output_file='outputs/ai_news_summary.txt',
    create_directory=True # <<<<<<<<<<<<<<<< Inexistent argument
)

#...
```

### Operating System

Windows 11

### Python Version

3.12

### crewAI Version

0.130.0

### crewAI Tools Version

0.118.0

### Virtual Environment

Poetry

### Evidence

<img width="564" height="74" alt="Image" src="https://github.com/user-attachments/assets/fd9d7f1f-629f-46c2-8f76-efd2802758bd" />

### Possible Solution

Just implement the parameter or remove it from the documentation.

### Additional context

No

### Additional contract requirements

When `create_directory` is `False`, saving output to a path whose parent directory does not exist must raise a `RuntimeError` without creating that directory.
