---
title: "Plugin SDK"
description: "Write plugins for LegacyPodClaw"
weight: 4
---

LegacyPodClaw includes a plugin SDK (`PluginSDK.h`) for extending the agent with custom tools.

## Overview

Plugins register custom tools that the AI agent can invoke. Each tool has:

- A name and description
- A JSON Schema defining its input parameters
- A handler block that executes the tool logic
- Optional: confirmation requirement, custom timeout

## Creating a Tool

```objc
#import "PluginSDK.h"
#import "Agent.h"

OCToolDefinition *myTool = [[OCToolDefinition alloc] init];
myTool.name = @"my_custom_tool";
myTool.toolDescription = @"Does something useful";
myTool.inputSchema = @{
    @"type": @"object",
    @"properties": @{
        @"query": @{
            @"type": @"string",
            @"description": @"The search query"
        }
    },
    @"required": @[@"query"]
};
myTool.requiresConfirmation = NO;
myTool.timeout = 30.0;

myTool.handler = ^(NSDictionary *params, OCToolResultBlock callback) {
    NSString *query = params[@"query"];
    // Do work...
    callback(@{@"result": @"success"}, nil);
};
```

## Registering with the Agent

```objc
[agent registerTool:myTool];
```

## MCP Server Integration

Plugins can also connect to external MCP (Model Context Protocol) servers:

```objc
OCMCPClient *client = [[OCMCPClient alloc] initWithURL:@"http://localhost:8080" name:@"my-server"];
[client connect:^(BOOL success, NSError *error) {
    if (success) {
        [agent addMCPServer:client];
    }
}];
```

Connected MCP servers automatically expose their tools to the agent.
