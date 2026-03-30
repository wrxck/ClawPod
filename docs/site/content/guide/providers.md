---
title: "AI Providers"
description: "Configure and use any of 10 supported AI providers"
weight: 2
---

LegacyPodClaw supports 10 AI providers with automatic failover. If your primary provider fails, the agent tries the next configured provider.

## Anthropic

The default provider. Supports Claude models.

- **Settings:** API Key
- **Models:** claude-sonnet-4-20250514, claude-haiku, and others
- **Base URL:** `https://api.anthropic.com` (default)

## OpenAI

- **Settings:** API Key
- **Models:** gpt-4o, gpt-4o-mini, and others
- **Base URL:** `https://api.openai.com` (default)

## Google / Gemini

- **Settings:** API Key
- **Models:** gemini-pro, gemini-flash, and others

## Ollama (Self-Hosted)

Run models locally on your network:

- **Settings:** Base URL (e.g. `http://192.168.1.100:11434`)
- **No API key needed**
- **Models:** Whatever you have pulled in Ollama

## Groq

- **Settings:** API Key
- **Fast inference** for supported open models

## Together AI

- **Settings:** API Key
- **Open-source models** (Llama, Mistral, etc.)

## OpenRouter

- **Settings:** API Key
- **Aggregator** — access multiple providers through one API key

## Mistral

- **Settings:** API Key
- **Models:** mistral-large, mistral-small, etc.

## Deepseek

- **Settings:** API Key
- **Models:** deepseek-chat, deepseek-reasoner

## Custom Endpoint

Any OpenAI-compatible API:

- **Settings:** Base URL + API Key
- Works with any service that implements the OpenAI chat completions format

## Failover

Configure multiple providers in Settings. If a request to your primary provider fails (timeout, rate limit, error), LegacyPodClaw automatically tries the next configured provider in order.
