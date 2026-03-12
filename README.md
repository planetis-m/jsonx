# jsonx

jsonx is a lightweight JSON serializer/deserializer for Nim with a small, fast parser.
It includes:
- A minimal streaming layer in `jsonx/streams`.
- A JSON lexer/parser in `jsonx/parsejson`.
- A macro-based object mapper and serializer in `jsonx` (top-level module).

## Layout
- `src/jsonx/streams.nim`: minimal stream API used by the parser.
- `src/jsonx/lexbase.nim`: lexer base with buffering.
- `src/jsonx/parsejson.nim`: JSON tokenizer + parser.
- `src/jsonx.nim`: serializer + object mapping.
- `tests/`: test suite.

## Usage

Serialize to a string:

```nim
import jsonx
import jsonx/streams

let out = toJson((hello: "world", answer: 42))
```

Deserialize from a string:

```nim
import jsonx

type Person = object
  name: string
  age: int

let p = fromJson("{\"name\":\"Ada\",\"age\":42}", Person)
```

Deserialize from a stream:

```nim
import jsonx
import jsonx/streams

type Person = object
  name: string
  age: int

let s = streams.open("{\"name\":\"Ada\",\"age\":42}")
let p = fromJson(s, Person)
```

Write to a stream / read from a parser:

```nim
import jsonx
import jsonx/streams

type Person = object
  name: string
  age: int

let s = streams.open("")
let p = Person(name: "Ada", age: 42)
s.writeJson(p)

var parsed: Person
var parser: JsonParser
open(parser, streams.open(s.s), "inline")
discard getTok(parser)
readJson(parsed, parser)
```

Custom read/write for your own types:

```nim
import jsonx
import jsonx/[parsejson, streams]

type
  ChatCompletionInputContentKind = enum
    text, parts

  ChatCompletionContentPart = object
    text: string

  ChatCompletionMessageContent = object
    case kind: ChatCompletionInputContentKind
    of text:
      text: string
    of parts:
      parts: seq[ChatCompletionContentPart]

  ChatMessage = object
    role: string
    content: ChatCompletionMessageContent

# Accept either:
# - "content": "plain text"
# - "content": [{ "text": "part 1" }, ...]
proc readJson*(dst: var ChatCompletionMessageContent; p: var JsonParser) =
  if p.tok == tkString:
    dst = ChatCompletionMessageContent(kind: text)
    readJson(dst.text, p)
  elif p.tok == tkBracketLe:
    dst = ChatCompletionMessageContent(kind: parts)
    readJson(dst.parts, p)
  else:
    raiseParseErr(p, "string or array")

# Write back with the same shape.
proc writeJson*(s: Stream; x: ChatCompletionMessageContent) =
  case x.kind
  of text:
    writeJson(s, x.text)
  of parts:
    writeJson(s, x.parts)
```

Capture and re-emit a raw JSON fragment:

```nim
import jsonx

type
  Envelope = object
    payload: RawJson

let env = fromJson(
  """{"payload": { "answer": [1, 2, 3], "ok": true }}""",
  Envelope
)

# RawJson stores normalized JSON text.
doAssert string(env.payload) == """{"answer":[1,2,3],"ok":true}"""
doAssert toJson(env) == """{"payload":{"answer":[1,2,3],"ok":true}}"""
```

State-aware output (emit only fields relevant to the current status):

```nim
import jsonx
import jsonx/streams

type
  PageErrorKind = enum
    NoError, NetworkError, HttpError, ParseError

  PageResultStatus = enum
    PagePending = "pending"
    PageOk = "ok"
    PageError = "error"

  PageResult = object
    page: int
    status: PageResultStatus
    text: string
    errorKind: PageErrorKind
    errorMessage: string
    httpStatus: int

template writeJsonField(s: Stream; name: string; value: untyped) =
  # Shared "key:value" writer with comma handling.
  if comma: s.write ","
  else: comma = true
  escapeJson(s, name)
  s.write ":"
  writeJson(s, value)

proc writeJson*(s: Stream; x: PageResult) =
  var comma = false
  s.write "{"
  writeJsonField(s, "page", x.page)
  writeJsonField(s, "status", x.status)
  case x.status
  of PageOk:
    writeJsonField(s, "text", x.text) # Success payload.
  of PageError:
    writeJsonField(s, "error_kind", x.errorKind)
    writeJsonField(s, "error_message", x.errorMessage)
    if x.httpStatus != 0:
      writeJsonField(s, "http_status", x.httpStatus) # Optional HTTP context.
  of PagePending:
    discard # Nothing extra to emit yet.
  s.write "}"

let ok = PageResult(page: 7, status: PageOk, text: "hello")
echo toJson(ok) # {"page":7,"status":"ok","text":"hello"}
```

```nim
# This data structure is like a Table[int, T],
# so we encode it as an array of [key, value] pairs.
proc writeJson*[T](s: Stream; a: SparseSet[T]) =
  s.write "["
  var comma = false
  for e, val in a.pairs:
    # Emit commas between pairs.
    if comma: s.write ","
    else: comma = true

    # Each entry is a 2-element JSON array: [entity, value].
    s.write "["
    writeJson(s, e)
    s.write ","
    writeJson(s, val)
    s.write "]"
  s.write "]"

proc readJson*[T](dst: var SparseSet[T]; p: var JsonParser) =
  eat(p, tkBracketLe)
  # Start from a clean container before filling parsed entries.
  dst = initSparseSet[T]()
  while p.tok != tkBracketRi:
    eat(p, tkBracketLe)
    var e: Entity
    readJson(e, p)
    eat(p, tkComma)
    var val: T
    readJson(val, p)
    dst[e] = val
    eat(p, tkBracketRi)
    # Accept either ',' + next item or closing ']'.
    expectArraySeparator(p)
  eat(p, tkBracketRi)
```

Iterate array items:

```nim
import jsonx
import jsonx/streams

let s = streams.open("[{\"name\":\"A\"},{\"name\":\"B\"}]")
for item in jsonItems(s, Person):
  discard
```

## Compile-Time Defines

Enable with `-d:<define>` or a module pragma like `{.define: <define>.}`.

| Define | Default | Effect |
| --- | --- | --- |
| `jsonxLenient` | off | Unknown object fields are skipped during deserialization instead of raising a parse error. |
| `jsonxNormalized` | off | Object field matching uses `nimIdentNormalize` (case/underscore-insensitive Nim-style matching) instead of exact JSON key matching. |

## Tests

Run from the repo root:

```sh
nim c -r tests/test.nim
nim c -r tests/test_parsejson.nim
nim c -r tests/test_numbers.nim
nim c -r tests/test_compliance.nim
```

## Benchmarks

Build flag: `-d:danger`

| Benchmark | Command | Time |
| --- | --- | --- |
| `std/json` | `nim c -d:danger -r bench/benchmark.nim` | `1.512484859s` |
| `jsonx` | `nim c -d:danger -r bench/benchmark_jsonx.nim` | `0.5514422219999999s` |
| `jsony` | `nim c -d:danger -r bench/benchmark_jsony.nim` | `0.640786663s` |
| `eminim` | `nim c -d:danger -r bench/benchmark_eminim.nim` | `0.711290562s` |
| `jsonx (ints)` | `nim c -d:danger -r bench/benchmark_jsonx_ints.nim` | `0.087715133s` |

In this run, `jsonx` is about `2.74x` faster than `std/json`, `jsony` is about `2.36x` faster than `std/json`, and `eminim` is about `2.13x` faster than `std/json`. `jsonx` is about `1.16x` faster than `jsony`.

### OpenAI API-like file benchmark

This benchmark parses a generated chat-completions style payload (`bench/openai/openai_chat_payload.json`, ~75MiB, 60,000 sessions with message/tool-call/usage data) to better represent OpenAI API usage.

| Benchmark | Command | Time |
| --- | --- | --- |
| `jsonx (openai)` | `nim c -d:danger -r bench/openai/benchmark_jsonx.nim` | `0.155633581s` (median of 3) |
| `jsony (openai)` | `nim c -d:danger -r bench/openai/benchmark_jsony.nim` | `0.153236498s` (median of 3) |

In this run, `jsony` is about `1.02x` faster than `jsonx` on the OpenAI API-like workload.
