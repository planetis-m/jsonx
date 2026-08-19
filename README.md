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
readJson(parsed, parser, ufSkip)
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
proc readJson*(dst: var ChatCompletionMessageContent; p: var JsonParser;
               unknownFields: UnknownFieldPolicy) =
  if p.tok == tkString:
    dst = ChatCompletionMessageContent(kind: text)
    readJson(dst.text, p, unknownFields)
  elif p.tok == tkBracketLe:
    dst = ChatCompletionMessageContent(kind: parts)
    readJson(dst.parts, p, unknownFields)
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

Model a forward-compatible `ResponseOutput` item with typed message data and an opaque fallback:

```nim
proc appendRawField(dst: var string; name: string; p: var JsonParser) =
  if dst.len == 0:
    dst.add('{')
  else:
    dst.add(',')
  escapeJson(name, dst)
  dst.add(':')
  appendRawJson(dst, p)

proc readJson*(dst: var ResponseOutput; p: var JsonParser;
               unknownFields: UnknownFieldPolicy) =
  var id, status, role: string
  var kind: ResponseOutputKind
  var content: seq[ResponseOutputPart]
  var extra = ""

  eat(p, tkCurlyLe)
  while p.tok != tkCurlyRi:
    if p.tok != tkString:
      raiseParseErr(p, "string literal as key")
    let fieldName = p.a
    discard getTok(p)
    eat(p, tkColon)
    case fieldName
    of "id": readJson(id, p, unknownFields)
    of "status": readJson(status, p, unknownFields)
    of "type": readJson(kind, p, unknownFields)
    of "role": readJson(role, p, unknownFields)
    of "content": readJson(content, p, unknownFields)
    else: appendRawField(extra, fieldName, p)

    if p.tok == tkComma:
      discard getTok(p)
    elif p.tok != tkCurlyRi:
      raiseParseErr(p, "',' or '}'")
  eat(p, tkCurlyRi)

  case kind
  of message:
    if unknownFields == ufReject and extra.len > 0:
      raiseParseErr(p, "known field for a message output")
    dst = ResponseOutput(
      id: id, status: status, `type`: kind, shape: outputMessage,
      message: ResponseOutputMessage(role: role, content: content)
    )
  else:
    if extra.len > 0:
      extra.add('}')
    dst = ResponseOutput(
      id: id, status: status, `type`: kind, shape: outputOpaque,
      extraFields: RawJson(extra)
    )
```

Work with arbitrary JSON payloads:

Use `RawJson` when a field needs to carry JSON without a dedicated Nim type.
Use `CanonRawJson` only when you need one stable representation for caching, hashing, or comparisons.

```nim
import jsonx

type
  ToolSpec = object
    name: string
    schema: RawJson

let tool = fromJson(
  """{"name":"extract_invoice","schema":{"type":"object","properties":{"vendor":{"type":"string"},"total":{"type":"number"}}}}""",
  ToolSpec
)

echo toJson(tool)
# {"name":"extract_invoice","schema":{"type":"object","properties":{"vendor":{"type":"string"},"total":{"type":"number"}}}}

let cacheKey = fromJson("""{"b":1,"a":2,"b":3}""", CanonRawJson)
echo toJson(cacheKey)
# {"a":2,"b":3}
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

proc readJson*[T](dst: var SparseSet[T]; p: var JsonParser;
                  unknownFields: UnknownFieldPolicy) =
  eat(p, tkBracketLe)
  # Start from a clean container before filling parsed entries.
  dst = initSparseSet[T]()
  while p.tok != tkBracketRi:
    eat(p, tkBracketLe)
    var e: Entity
    readJson(e, p, unknownFields)
    eat(p, tkComma)
    var val: T
    readJson(val, p, unknownFields)
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

let strictStream = streams.open("[{\"name\":\"A\"}]")
for item in jsonItems(strictStream, Person, ufReject):
  discard
```

## Unknown object fields

`UnknownFieldPolicy` has two values:

- `ufSkip` skips unknown object fields and is the default.
- `ufReject` raises `JsonParsingError` when an object contains an unknown field.

Known fields remain type-checked in both modes, and malformed JSON always fails. Select the policy
per decoding operation:

```nim
let compatible = fromJson(payload, Person)
let strict = fromJson(payload, Person, unknownFields = ufReject)
```

The selected policy propagates through nested objects, sequences, tables, references, options,
tuples, `fromFile`, and `jsonItems`. Custom `readJson` implementations must accept and forward it:

```nim
proc readJson*(dst: var Wrapper; p: var JsonParser;
               unknownFields: UnknownFieldPolicy) =
  readJson(dst.value, p, unknownFields)
```

The former `jsonxLenient` compile-time define is no longer needed: lenient decoding is now the
default, while strict decoding is selected at runtime with `ufReject`.

## Compile-Time Defines

Enable with `-d:<define>` or a module pragma like `{.define: <define>.}`.

| Define | Default | Effect |
| --- | --- | --- |
| `jsonxNormalized` | off | Object field matching uses `nimIdentNormalize` (case/underscore-insensitive Nim-style matching) instead of exact JSON key matching. This remains compile-time so object readers generate only one matching branch. |

## Tests

Run from the repo root:

```sh
nim c -r tests/test.nim
nim c -r tests/test_parsejson.nim
nim c -r tests/test_numbers.nim
nim c -r tests/test_compliance.nim
```

## Benchmarks

Local benchmark dependencies (`jsony`, `eminim`) are fetched into `bench/deps` via atlas:
`cd bench && atlas install`. The OpenAI benchmark keeps its own copy under `bench/openai/deps` (`cd bench/openai && atlas install`).

Build flag: `-d:danger`, invoked as `nim c -d:danger -r <file>`. Times are the median of 3 runs and include file I/O.

### Coordinates payload

`bench/1.json` (~211MiB) holds 1,000,000 `{x, y, z}` coordinates and is generated by `bench/generator.nim` (the classic JSON benchmark):

| Benchmark | File | Time | vs `std/json` |
| --- | --- | --- | --- |
| `std/json` | `bench/benchmark.nim` | `1.672s` | 1.00x |
| `jsonx` | `bench/benchmark_jsonx.nim` | `0.518s` | 3.23x |
| `jsony` | `bench/benchmark_jsony.nim` | `0.495s` | 3.38x |
| `eminim` | `bench/benchmark_eminim.nim` | `0.715s` | 2.34x |

`bench/benchmark_jsonx_ints.nim` times pure int parsing of 1,000,000 `int64` values from an in-memory payload (no file I/O): `0.051s`.

### OpenAI API-like payload

`bench/openai/openai_chat_payload.json` (~75MiB) holds 60,000 chat-completions sessions with message, tool-call, and usage data, generated by `bench/openai/generator.nim`:

| Benchmark | File | Time | vs `jsonx` |
| --- | --- | --- | --- |
| `jsonx (openai)` | `bench/openai/benchmark_jsonx.nim` | `0.217s` | 1.00x |
| `jsony (openai)` | `bench/openai/benchmark_jsony.nim` | `0.137s` | 1.58x |
