Composed MCP Servers don't initialize lifespans
When an MCP Server is composed, the current code imports the tools but does not start-up the lifespan


This means you still need one giant lifespan function at the top level that initializes the lifespans of all the child servers. It would be nice if the composing FastMCP handled this for you.
