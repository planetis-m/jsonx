## Generates a chat-completions style payload for the OpenAI API-like benchmark.
## Produces bench/openai/openai_chat_payload.json: a JSON array of 60,000
## chat completion responses with message/tool-call/usage data (~75MiB).

import std/[os, strutils]

const
  Sessions = 60_000
  OutPath = currentSourcePath().parentDir() / "openai_chat_payload.json"
  ToolNames = ["get_weather", "web_search", "run_code"]

proc content(i: int): string =
  # Vary message length like real traffic: 1..11 sentences (average ~6).
  let sentences = 1 + ((i * 7) mod 11)
  result = "This is a simulated chat completion response for session " & $i & "."
  for j in 0 ..< sentences:
    result.add " The model generated sentence number " & $j &
      " containing roughly a hundred characters of representative English text with numbers like " &
      $(i * 13 + j * 7) & "."
  result.add " This payload mimics a real chat completion result with a moderate response length."

proc toolArguments(i: int): string =
  "{\\\"city\\\":\\\"City" & $i & "\\\",\\\"units\\\":\\\"metric\\\",\\\"days\\\":" &
    $(1 + (i mod 7)) & "}"

proc messageBlock(i: int): string =
  let msg = content(i)
  if i mod 4 == 0:
    # Assistant message with one function tool call.
    result = "{\"role\":\"assistant\",\"content\":\"" & msg & "\"" &
      ",\"tool_calls\":[{\"id\":\"call_" & $i &
      "\",\"type\":\"function\",\"function\":{\"name\":\"" & ToolNames[i mod 3] &
      "\",\"arguments\":\"" & toolArguments(i) & "\"}}],\"tool_call_id\":\"\"}"
  elif i mod 8 == 0:
    # Tool result message referencing a previous tool call.
    result = "{\"role\":\"tool\",\"content\":\"{\\\"temperature\\\":" &
      $(10 + i mod 25) & ",\\\"condition\\\":\\\"sunny\\\"}\"" &
      ",\"tool_calls\":[],\"tool_call_id\":\"call_" & $i & "\"}"
  else:
    result = "{\"role\":\"assistant\",\"content\":\"" & msg & "\"" &
      ",\"tool_calls\":[],\"tool_call_id\":\"\"}"

proc session(i: int): string =
  let finishReason =
    if i mod 4 == 0: "tool_calls"
    elif i mod 16 == 2: "length"
    else: "stop"
  let prompt = 200 + (i * 7) mod 4000
  let completion = 100 + (i * 13) mod 2000
  result = "{\"id\":\"chatcmpl-" & $i & "-aaaaaaaaaaaaaaaa\"" &
    ",\"object\":\"chat.completion\",\"created\":" & $(1_720_000_000 + i) &
    ",\"model\":\"gpt-4o-2024-08-06\",\"choices\":[{\"index\":0,\"message\":" &
    messageBlock(i) & ",\"finish_reason\":\"" & finishReason & "\"}]" &
    ",\"usage\":{\"prompt_tokens\":" & $prompt & ",\"completion_tokens\":" & $completion &
    ",\"total_tokens\":" & $(prompt + completion) & "}}"

var payload = newStringOfCap(Sessions * 1300)
payload.add '['
for i in 0 ..< Sessions:
  if i > 0:
    payload.add ','
  payload.add session(i)
payload.add ']'

writeFile(OutPath, payload)
echo "wrote ", OutPath, " (", formatSize(payload.len), ")"
