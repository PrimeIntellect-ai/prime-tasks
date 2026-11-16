[BUG]If only system_template is provided and prompt_template is missing,error occurred!
### Description

The CrewAI framework throws an AttributeError: 'NoneType' object has no attribute 'replace' when attempting to execute a Crew with an Agent configured with only the system_template parameter, while the prompt_template is left undefined (i.e., None).
And ,if prompt_template proveded also,but response_template not provided,error occurred also!

### Steps to Reproduce

simple example

### Expected behavior

no error,if these three parameters are optional

### Screenshots/Code snippets

from crewai import Agent, Task, Crew

# Incorrect Agent configuration (missing prompt_template)
designer = Agent(
  name="WeChat Layout Expert",
  role="WeChat Layout Expert",
  goal="Design and optimize the generated article for WeChat public accounts.",
  backstory="You are a professional WeChat public account layout designer, familiar with WeChat layout rules.",
  allow_delegation=False,
  memory=True,
  max_rpm=150,
  system_template="You are a professional WeChat public account layout designer...", # system_template present
  # prompt_template is missing
)

# Task and Crew setup (example)
task = Task(description="Layout task", agent=designer)
crew = Crew(agents=[designer], tasks=[task])

# Attempting to execute the Crew will result in the error
crew.kickoff()

### Operating System

Windows 11

### Python Version

3.10

### crewAI Version

102

### crewAI Tools Version

no tool

### Virtual Environment

Venv

### Evidence

Traceback (most recent call last):
  File "C:\Users\X\Desktop\test\src\test\main.py", line 26, in run
    Test().crew().kickoff(inputs=inputs)
    ^^^^^^^^^^^
  File "C:\Users\X\AppData\Local\Programs\Python\Python311\Lib\site-packages\crewai\project\crew_base.py", line 36, in __init__
    self.map_all_task_variables()
  File "C:\Users\X\AppData\Local\Programs\Python\Python311\Lib\site-packages\crewai\project\crew_base.py", line 203, in map_all_task_variables
    self._map_task_variables(
  File "C:\Users\X\AppData\Local\Programs\Python\Python311\Lib\site-packages\crewai\project\crew_base.py", line 236, in _map_task_variables
    self.tasks_config[task_name]["agent"] = agents[agent_name]()
                                            ^^^^^^^^^^^^^^^^^^^^
  File "C:\Users\X\AppData\Local\Programs\Python\Python311\Lib\site-packages\crewai\project\utils.py", line 11, in memoized_func
    cache[key] = func(*args, **kwargs)
                 ^^^^^^^^^^^^^^^^^^^^^
  File "C:\Users\X\Desktop\test\src\test\crew.py", line 37, in designer
    return Agent(
           ^^^^^^
  File "C:\Users\X\AppData\Local\Programs\Python\Python311\Lib\site-packages\pydantic\main.py", line 214, in __init__
    validated_self = self.__pydantic_validator__.validate_python(data, self_instance=self)
                     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "C:\Users\X\AppData\Local\Programs\Python\Python311\Lib\site-packages\crewai\agent.py", line 133, in post_init_setup
    self._setup_agent_executor()
  File "C:\Users\X\AppData\Local\Programs\Python\Python311\Lib\site-packages\crewai\agent.py", line 143, in _setup_agent_executor
    self.set_cache_handler(self.cache_handler)
  File "C:\Users\X\AppData\Local\Programs\Python\Python311\Lib\site-packages\crewai\agents\agent_builder\base_agent.py", line 341, in set_cache_handler
    self.create_agent_executor()
  File "C:\Users\X\AppData\Local\Programs\Python\Python311\Lib\site-packages\crewai\agent.py", line 291, in create_agent_executor
    ).task_execution()
      ^^^^^^^^^^^^^^^^
  File "C:\Users\X\AppData\Local\Programs\Python\Python311\Lib\site-packages\crewai\utilities\prompts.py", line 41, in task_execution
    "prompt": self._build_prompt(
              ^^^^^^^^^^^^^^^^^^^
  File "C:\Users\X\AppData\Local\Programs\Python\Python311\Lib\site-packages\crewai\utilities\prompts.py", line 67, in _build_prompt
    prompt = prompt_template.replace(
             ^^^^^^^^^^^^^^^^^^^^^^^
AttributeError: 'NoneType' object has no attribute 'replace'

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "C:\Users\X\Desktop\test\src\test\main.py", line 175, in <module>
    test()
  File "C:\Users\X\Desktop\test\src\test\main.py", line 171, in test
    run(inputs)
  File "C:\Users\X\Desktop\test\src\test\main.py", line 28, in run
    raise Exception(f"An error occurred while running the crew: {e}")
Exception: An error occurred while running the crew: 'NoneType' object has no attribute 'replace'
---------------
Traceback (most recent call last):
  File "C:\Users\XX\Desktop\test\src\test\main.py", line 26, in run
    Test().crew().kickoff(inputs=inputs)
    ^^^^^^^^^^^
  File "C:\Users\XX\AppData\Local\Programs\Python\Python311\Lib\site-packages\crewai\project\crew_base.py", line 36, in __init__
    self.map_all_task_variables()
  File "C:\Users\XX\AppData\Local\Programs\Python\Python311\Lib\site-packages\crewai\project\crew_base.py", line 203, in map_all_task_variables
    self._map_task_variables(
  File "C:\Users\XX\AppData\Local\Programs\Python\Python311\Lib\site-packages\crewai\project\crew_base.py", line 236, in _map_task_variables
    self.tasks_config[task_name]["agent"] = agents[agent_name]()
                                            ^^^^^^^^^^^^^^^^^^^^
  File "C:\Users\XX\AppData\Local\Programs\Python\Python311\Lib\site-packages\crewai\project\utils.py", line 11, in memoized_func
    cache[key] = func(*args, **kwargs)
                 ^^^^^^^^^^^^^^^^^^^^^
  File "C:\Users\XX\Desktop\test\src\test\crew.py", line 37, in designer
    return Agent(
           ^^^^^^
  File "C:\Users\XX\AppData\Local\Programs\Python\Python311\Lib\site-packages\pydantic\main.py", line 214, in __init__
    validated_self = self.__pydantic_validator__.validate_python(data, self_instance=self)
                     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "C:\Users\XX\AppData\Local\Programs\Python\Python311\Lib\site-packages\crewai\agent.py", line 133, in post_init_setup
    self._setup_agent_executor()
  File "C:\Users\XX\AppData\Local\Programs\Python\Python311\Lib\site-packages\crewai\agent.py", line 143, in _setup_agent_executor
    self.set_cache_handler(self.cache_handler)
  File "C:\Users\XX\AppData\Local\Programs\Python\Python311\Lib\site-packages\crewai\agents\agent_builder\base_agent.py", line 341, in set_cache_handler
    self.create_agent_executor()
  File "C:\Users\XX\AppData\Local\Programs\Python\Python311\Lib\site-packages\crewai\agent.py", line 291, in create_agent_executor
    ).task_execution()
      ^^^^^^^^^^^^^^^^
  File "C:\Users\XX\AppData\Local\Programs\Python\Python311\Lib\site-packages\crewai\utilities\prompts.py", line 41, in task_execution
    "prompt": self._build_prompt(
              ^^^^^^^^^^^^^^^^^^^
  File "C:\Users\XX\AppData\Local\Programs\Python\Python311\Lib\site-packages\crewai\utilities\prompts.py", line 70, in _build_prompt
    response = response_template.split("{{ .Response }}")[0]
               ^^^^^^^^^^^^^^^^^^^^^^^
AttributeError: 'NoneType' object has no attribute 'split'

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "C:\Users\XX\Desktop\test\src\test\main.py", line 175, in <module>
    test()
  File "C:\Users\XX\Desktop\test\src\test\main.py", line 171, in test
    run(inputs)
  File "C:\Users\XX\Desktop\test\src\test\main.py", line 28, in run
    raise Exception(f"An error occurred while running the crew: {e}")
Exception: An error occurred while running the crew: 'NoneType' object has no attribute 'split'

### Possible Solution

i dont know

### Additional context

use system_template（prompt_template、response_template provided）,gemini cant run correctly,,,but deepseek 、qwq32b run no error
