Skill name is not defined
### System Info

OS version: macOS 14.5
Python version: Python 3.10.7
The current version of pandasai being used: 2.2.12

### 🐛 Describe the bug

# Bug: Skill Calculations Fail in PandasAI

## Issue Description
Skills that perform calculations are failing with a `NameError: name '<skill>' is not defined` error. [HIDDEN]

The `get_environment()` function returns a dictionary with pandas, matplotlib, numpy, and some whitelisted builtins, but no skills:

```python
def get_environment(additional_deps: List[dict]) -> dict:
    return {
        "pd": pd,
        "plt": plt,
        "np": np,
        # Additional dependencies and whitelisted builtins...
    }
```

## Contrast with Correct Implementation
In contrast, the `execute_code` method in the `CodeExecution` class correctly adds skills to the environment:

```python
def execute_code(self, code: str, context: ExecutionContext):
    # ...
[HIDDEN]
    # ...
```

## Proposed Solution
[HIDDEN]

## Example
```
import os

import pandas as pd

from pandasai import Agent
from pandasai.skills import skill
from pandasai.llm import OpenAI

employees_data = {
    "EmployeeID": [1, 2, 3, 4, 5],
    "Name": ["John", "Emma", "Liam", "Olivia", "William"],
    "Department": ["HR", "Sales", "IT", "Marketing", "Finance"],
}

salaries_data = {
    "EmployeeID": [1, 2, 3, 4, 5],
    "Salary": [5000, 6000, 4500, 7000, 5500],
}

employees_df = pd.DataFrame(employees_data)
salaries_df = pd.DataFrame(salaries_data)


# Add function docstring to give more context to model
@skill
def plot_salaries(names: list[str], salaries: list[int]):
    """
    Displays the bar chart having name on x-axis and salaries on y-axis using matplotlib
    Args:
        names (list[str]): Employees' names
        salaries (list[int]): Salaries
    """
    import matplotlib.pyplot as plt

    plt.bar(names, salaries)
    plt.xlabel("Employee Name")
    plt.ylabel("Salary")
    plt.title("Employee Salaries")
    plt.xticks(rotation=45)


@skill
def calculate_salary_betas(salaries: list[int]) -> list[float]:
    """
    Calculates the betas (25th, 50th and 75th percentiles) of salaries.

    Args:
        salaries (list[int]): List of employee salaries

    Returns:
        list[float]: A list containing the 25th, 50th, and 75th percentiles
    """
    import numpy as np

    percentiles = np.percentile(salaries, [25, 50, 75])
    return percentiles.tolist()


# By default, unless you choose a different LLM, it will use BambooLLM.
# You can get your free API key signing up at https://pandabi.ai (you can also configure it in your .env file)
llm = OpenAI(
    api_token=os.getenv("OPENAI_API_KEY"), temperature=0, seed=26, model="gpt-4o"
)
agent = Agent(
    [employees_df, salaries_df],
    config={"llm": llm, "enforce_privacy": True},
    memory_size=10,
)
agent.add_skills(plot_salaries, calculate_salary_betas)

# Chat with the agent
response = agent.chat("Create a table with salary betas")
```
Error:
```
Traceback (most recent call last):
  File "pandas-ai/pandasai/pipelines/chat/code_cleaning.py", line 95, in execute
    code_to_run = self.get_code_to_run(input, code_context)
  File "pandas-ai/pandasai/pipelines/chat/code_cleaning.py", line 152, in get_code_to_run
    code_to_run = self._clean_code(code, context)
  File "pandas-ai/pandasai/pipelines/chat/code_cleaning.py", line 515, in _clean_code
    self._extract_fix_dataframe_redeclarations(node, clean_code_lines)
  File "pandas-ai/pandasai/pipelines/chat/code_cleaning.py", line 420, in _extract_fix_dataframe_redeclarations
    exec(code, env)
  File "<string>", line 5, in <module>
NameError: name 'calculate_salary_betas' is not defined
```

### Additional contract requirements

- When code cleaning evaluates dataframe-construction code that invokes a skill used in the current execution context, that skill must be available during evaluation so the code does not fail with a `NameError`.
