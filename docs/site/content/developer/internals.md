---
title: "Internals"
description: "Agent runtime, provider registry, tool system, and channel manager"
weight: 6
---

Deep dive into LegacyPodClaw's core subsystems.

## Agent Runtime

The `OCAgent` class (`Frameworks/Agent/Agent.h`) is the core AI runtime:

- **Tool orchestration:** Register tools, the agent decides when to call them
- **HTTP model routing:** Sends requests to configured AI providers via `OCModelHTTPClient`
- **MCP client:** Connects to external tool servers via `OCMCPClient`
- **Context management:** Token budget tracking, auto-compaction when over budget
- **Streaming:** Chunked transfer encoding via `NSURLConnection` (iOS 6 compatible — no `NSURLSession`)

### Token Budgets

- `maxContextTokens`: 4096 (default, conservative for 256MB devices)
- `maxResponseTokens`: 1024
- Token estimation: `chars / 4` (rough heuristic)
- Auto-compaction summarises old messages when context exceeds budget

### Delegate Pattern

The agent communicates via `OCAgentDelegate`:

- `agent:didProduceText:isFinal:` — streaming text output
- `agent:didFailWithError:` — error handling
- `agent:willInvokeTool:withParams:` — tool call notification
- `agent:didInvokeTool:result:` — tool result notification
- `agent:didStartThinking:` — thinking/reasoning output
- `agent:tokenUsage:output:` — token usage tracking

## Provider Registry

`OCProviderRegistry` (`Frameworks/Providers/ProviderRegistry.h`) manages AI providers:

- Each provider implements the `OCModelProvider` protocol
- Providers: Anthropic, OpenAI, Google, Ollama, Groq, Together, OpenRouter, Mistral, Deepseek, Custom
- **Model routing:** `providerForModel:` finds the right provider for a model ID
- **Failover:** `chatCompletionWithFailover:models:onChunk:completion:` tries providers in order

### Markdown Processing

`OCMarkdownProcessor` converts markdown to:

- Plain text (strip formatting)
- HTML
- Telegram-compatible formatting
- IRC formatting (bold, italic, colours)

### Cron Parser

`OCCronParser` provides 5-field cron expression parsing for scheduled tasks.

## Tool System

Tools are defined as `OCToolDefinition` objects:

- `name` — tool identifier
- `toolDescription` — what the tool does (sent to the model)
- `inputSchema` — JSON Schema for parameters
- `handler` — block that executes the tool
- `requiresConfirmation` — whether to prompt the user
- `timeout` — per-tool timeout (default 30s)

### Guardrails

`OCGuardrails` (`Frameworks/Tools/Guardrails.h`) enforces safety:

- Blocklist of dangerous commands
- Protected system paths
- Rate limiting on tool execution
- Confirmation prompts for destructive operations

## Channel Manager

`OCChannelManager` (`Frameworks/Channels/ChannelManager.h`) coordinates platform bridges:

- Each channel implements a common protocol
- Messages from external platforms are routed to the agent
- Agent responses are formatted for each platform (markdown → IRC, markdown → Telegram, etc.)
- Channels: Telegram, Discord, IRC, Slack, Webhooks
