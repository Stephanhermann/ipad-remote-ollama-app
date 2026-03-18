---
name: create-prompt
description: "Create a reusable prompt file (.prompt.md) for a repeatable task, based on conversation patterns and user intent."
argument-hint: What task should the prompt help automate? (e.g., "generate unit tests for a Swift class")
agent: agent
---

Related skill: `agent-customization`. Use the guidelines in `agent-customization` and follow prompt file conventions.

Guide the user to create a `.prompt.md` file.

## Extract from Conversation
When invoked, look for repetition in the conversation. Identify:
- The core task being performed repeatedly (e.g., refactoring, writing tests, fixing style issues)
- Any implicit inputs (selected code, file type, project context)
- The desired output format, tone, or structure

## Clarify if Needed
If the task is unclear, ask the user:
- What exactly should this prompt automate?
- What inputs should the prompt accept (e.g., selection, file path, keywords)?
- What output format or structure is expected?
- Should the prompt be workspace-scoped or personal?

## Iterate
1. Draft the `.prompt.md` content (YAML frontmatter + prompt body).
2. Ask the user about any ambiguity (inputs, output style, examples).
3. Once confirmed, save the final prompt file and explain how to invoke it.

**Note:** The goal of the resulting `.prompt.md` is to let someone run it later as a single slash-command, producing consistent outputs for the defined task.