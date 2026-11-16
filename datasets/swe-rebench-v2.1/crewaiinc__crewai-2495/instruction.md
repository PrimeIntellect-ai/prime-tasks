[BUG] AttributeError in CrewAI MemoryClient using Gemini Api Key with Mem0 (self.um.search())
### Description

I encountered an issue when using CrewAI with Mem0 as the memory provider and Google Gemini 2.0 as the LLM The error occurs in ContextualMemory when trying to fetch user memory.

I tried the code with

client = MemoryClient()

and

client = MemoryClient(
    api_key="api key directly",
    org_id="my org id",
    project_id="my proj id"
)


### Steps to Reproduce

Install crewai and mem0ai using: pip install crewai mem0ai

import os
from crewai import Crew, Process
from mem0 import MemoryClient
os.environ["MEM0_API_KEY"] = userdata.get('MEM0_API_KEY')
client = MemoryClient()
messages = [
    {"role": "user", "content": "Hi there! I'm planning a vacation and could use some advice."},
     {"role": "assistant", "content": "Hello! I'd be happy to help with your vacation planning. What kind of destination do you prefer?"},
     {"role": "user", "content": "I am more of a beach person than a mountain person."},
     {"role": "assistant", "content": "That's interesting. Do you like hotels or Airbnb?"},
     {"role": "user", "content": "I like Airbnb more."},
 ]
 client.add(messages, user_id="john")

agent = Agent(
    role="About User",
    goal="You know everything about the user.",
    backstory="""You are a master at understanding people and their preferences.""",
    verbose=True,
    allow_delegation=False,
    llm=llm1, #the llm1 is saved in the os.environ
)
task = Task(
    description="Answer the following questions about the user: {question}",
    expected_output="An answer to the question.",
    agent=agent,
)

crew = Crew(
    agents=[agent],
    tasks=[task],
    process = Process.sequential,
    verbose=True,
    memory=True,
    memory_config={
        "provider": "mem0",
        "config": {"user_id": "john"},
    },
)

crew.kickoff(inputs={"question": "What is your favorite vacation destination?"})

### Expected behavior

Expected Behavior:
The CrewAI agent should retrieve user memory from Mem0.

Actual Behavior:
AttributeError: 'NoneType' object has no attribute 'search'



### Screenshots/Code snippets

Memory is not properly fetched, and self.um.search() raises an AttributeError.

### Operating System

Windows 11

### Python Version

3.12

### crewAI Version

0.108.0

### crewAI Tools Version

0.36.0

### Virtual Environment

Venv

### Evidence

╭──────────────────────────────────────────── Crew Execution Started ─────────────────────────────────────────────╮
│                                                                                                                 │
│  Crew Execution Started                                                                                         │
│  Name: crew                                                                                                     │
│  ID: 8e2eaa6a-2452-4dd1-9c32-44202e69dc7d                                                                       │
│                                                                                                                 │
│                                                                                                                 │
╰─────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
🚀 Crew: crew
└── 📋 Task: bfa624c9-c5a8-49cd-adbd-4ebf815c197f
       Status: Executing Task...
🚀 Crew: crew
└── 📋 Task: bfa624c9-c5a8-49cd-adbd-4ebf815c197f
       Assigned to: About User
       Status: ❌ Failed
╭───────────────────────────────────────────────── Task Failure ──────────────────────────────────────────────────╮
│                                                                                                                 │
│  Task Failed                                                                                                    │
│  Name: bfa624c9-c5a8-49cd-adbd-4ebf815c197f                                                                     │
│  Agent: About User                                                                                              │
│                                                                                                                 │
│                                                                                                                 │
╰─────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
╭───────────────────────────────────────────────── Crew Failure ──────────────────────────────────────────────────╮
│                                                                                                                 │
│  Crew Execution Failed                                                                                          │
│  Name: crew                                                                                                     │
│  ID: 8e2eaa6a-2452-4dd1-9c32-44202e69dc7d                                                                       │
│                                                                                                                 │
│                                                                                                                 │
╰─────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
---------------------------------------------------------------------------
AttributeError                            Traceback (most recent call last)
<ipython-input-17-9c5d753f3927> in <cell line: 0>()
     47 )
     48
---> 49 result = crew.kickoff(inputs={"question": "What is your favorite vacation destination?"})
     50
     51 # ✅ Output print karna

8 frames
/usr/local/lib/python3.11/dist-packages/crewai/memory/contextual/contextual_memory.py in _fetch_user_context(self, query)
     95             str: Formatted user memories as bullet points, or an empty string if none found.
     96         """
---> 97         user_memories = self.um.search(query)
     98         if not user_memories:
     99             return ""

AttributeError: 'NoneType' object has no attribute 'search'

### Possible Solution

class ContextualMemory:
    def __init__(
        self,
        memory_config: Optional[Dict[str, Any]],
        stm: ShortTermMemory,
        ltm: LongTermMemory,
        em: EntityMemory,
        um: UserMemory,
    ):
        if memory_config is not None:
            self.memory_provider = memory_config.get("provider")
            #  Testing the Mem0 client as if provider is "mem0"
[HIDDEN]
            else:
                self.um = um
        else:
            self.memory_provider = None
            self.um = um

### Additional context

The issue might be due to self.um being None in ContextualMemory.

### Additional contract requirements

- When the memory provider is `mem0` and no user memory is configured, building the contextual memory for a task must not raise an error; the task context is produced without any user-memory section.
- When user memory is configured, the memories returned by the user-memory search are included in the contextual information built for the task.
- When the provider is `mem0`, no user memory is configured, and there is no other memory context, `ContextualMemory.build_context_for_task(task, "")` must return exactly `""`.
