[BUG]Mem0 local config not being applied
### Description

[HIDDEN]

Should be

if mem0_local_config and len(mem0_local_config):
                [HIDDEN]

Just try using mem0 with a local config. I am attempting to use Gemini as an embedder but the exceptions I get state the OpenAI API key is not set.

### Expected behavior

The local config should be applied

### Screenshots/Code snippets

embedder_config = {
    "provider": "google",
    "config": {
        "model": "models/text-embedding-004",
        "api_key": GEMINI_API_KEY,
    }
}
----
@crew
    def crew(self) -> Crew:
        """Creates the TedCrew crew"""

        return Crew(
            agents=self.agents,
            tasks=self.tasks,
            process=Process.sequential,
            verbose=True,
            memory=True,
            memory_config={
                "provider": "mem0",
                "config": {"user_id": "tedcrew", 'local_mem0_config': mem0_config},
                "user_memory" : {} #Set user_memory explicitly to a dictionary, we are working on this issue.
            },
            # Long-term memory for persistent storage across sessions
            long_term_memory = LongTermMemory(
                storage=LTMSQLiteStorage(
                    db_path=f"{DATA_DIR}/long_term_memory_storage.db"
                )
            ),
            # Short-term memory for current context using RAG
            short_term_memory = ShortTermMemory(
                storage = RAGStorage(
                        embedder_config=embedder_config,
                        type="short_term",
                        path=f"{DATA_DIR}/"
                    )
            ),
            # Entity memory for tracking key information about entities
            entity_memory = EntityMemory(
                storage=RAGStorage(
                    embedder_config=embedder_config,
                    type="short_term",
                    path=f"{DATA_DIR}/"
                )
            ),
            embedder=embedder_config
        )

### Operating System

macOS Sonoma

### Python Version

3.12

### crewAI Version

0.114.0

### crewAI Tools Version

0.40.1

### Virtual Environment

Venv

### Evidence

<img width="1059" alt="Image" src="https://github.com/user-attachments/assets/bf0f8d50-708d-4cc8-9a2a-e10950a173fa" />

[HIDDEN]

Should be

if mem0_local_config and len(mem0_local_config):
                [HIDDEN]

None

### Additional contract requirements

- When a local Mem0 configuration is provided for agent memory, use that configuration to initialize the Mem0 backend so its provider and embedder settings are honored.
