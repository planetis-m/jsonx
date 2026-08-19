## Benchmark jsonx on a chat-completions style payload:

import std/[strutils, times, os]
import jsonx

type
  ToolFunction = object
    name: string
    arguments: string

  ToolCall = object
    id: string
    `type`: string
    function: ToolFunction

  Message = object
    role: string
    content: string
    tool_calls: seq[ToolCall]
    tool_call_id: string

  Choice = object
    index: int
    message: Message
    finish_reason: string

  Usage = object
    prompt_tokens: int
    completion_tokens: int
    total_tokens: int

  ChatCompletion = object
    id: string
    `object`: string
    created: int64
    model: string
    choices: seq[Choice]
    usage: Usage

let payloadPath = currentSourcePath().parentDir() / "openai_chat_payload.json"
let payload = readFile(payloadPath)

proc main =
  let completions = fromJson(payload, seq[ChatCompletion])

  doAssert completions.len == 60_000
  var totalTokens = 0
  var textLen = 0
  var toolCalls = 0
  for c in completions:
    totalTokens += c.usage.total_tokens
    textLen += c.choices[0].message.content.len
    toolCalls += c.choices[0].message.tool_calls.len

  echo totalTokens
  echo textLen
  echo toolCalls

let start = cpuTime()
main()
echo "used Mem: ", formatSize getOccupiedMem(), " time: ", cpuTime() - start, "s"
