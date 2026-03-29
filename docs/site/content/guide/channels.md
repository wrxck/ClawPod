---
title: "Channels"
description: "Connect LegacyPodClaw to Telegram, Discord, IRC, Slack, and webhooks"
weight: 5
---

When running the gateway server, LegacyPodClaw can bridge to external chat platforms.

## Telegram

Connect a Telegram bot to your device:

1. Create a bot via [@BotFather](https://t.me/botfather)
2. Enter the bot token in **Settings > LegacyPodClaw > Channels > Telegram**
3. Messages to your bot are processed by the on-device AI

## Discord

1. Create a Discord bot in the [Developer Portal](https://discord.com/developers)
2. Enter the bot token in **Settings > LegacyPodClaw > Channels > Discord**
3. The bot responds in channels it's added to

## IRC

Connect to any IRC network:

1. Enter server, port, nick, and channel in **Settings > LegacyPodClaw > Channels > IRC**
2. The AI responds to messages in the configured channel

Markdown formatting is automatically converted to IRC formatting (bold, italic, etc.).

## Slack

1. Create a Slack app with bot permissions
2. Enter the bot token in **Settings > LegacyPodClaw > Channels > Slack**

## Webhooks

Generic webhook integration for any platform:

1. Configure an incoming webhook URL in **Settings > LegacyPodClaw > Channels > Webhooks**
2. LegacyPodClaw POSTs AI responses to the webhook URL
