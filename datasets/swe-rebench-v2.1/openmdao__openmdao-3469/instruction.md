openmdao command running scripts results in incorrect Problem name and name for reports directory
### Description

A Problem created in a script and run with the python command has the correct name, which is the name of the script minus the extension.

But when the script is run using the openmdao command, the Problem name is `openmdao`. This results in the reports directory being name `openmdao_out`, which is not the desired behavior. It should also be the script name.

### Example

Here is a script that can be used to show the problem. Assume the name of the script is `model_script.py`

```
import openmdao.api as om
prob = om.Problem()
prob.setup()
prob.final_setup()
print(f'{prob._name=}')

```

Then run the script using python and openmdao to see the difference

```
$ python model_script.py
prob._name='model_script'
$ openmdao model_script.py
prob._name='openmdao'
```

### OpenMDAO Version

3.37.1-dev

### Relevant environment information

_No response_
