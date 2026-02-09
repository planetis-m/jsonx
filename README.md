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
# This data structure is like a Table[int, T],
# we resort to using arrays for the (key, value) pairs.

proc writeJson*[T](s: Stream; a: SparseSet[T]) =
  s.write "["
  var comma = false
  for e, val in a.pairs:
    if comma: s.write ","
    else: comma = true
    s.write "["
    writeJson(s, e)
    s.write ","
    writeJson(s, val)
    s.write "]"
  s.write "]"

proc readJson*[T](dst: var SparseSet[T]; p: var JsonParser) =
  eat(p, tkBracketLe)
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

| Benchmark | Command | Time | Memory |
| --- | --- | --- | --- |
| `std/json` | `nim c -d:danger -r bench/benchmark.nim` | `1.625880432s` | `20KiB` |
| `jsonx` | `nim c -d:danger -r bench/benchmark_jsonx.nim` | `0.6325633380000001s` | `0B` |
| `jsony` | `nim c -d:danger -r bench/benchmark_jsony.nim` | `0.680055153s` | `0B` |
| `eminim` | `nim c -d:danger -r bench/benchmark_eminim.nim` | `0.712659141s` | `20KiB` |
| `jsonx (ints)` | `nim c -d:danger -r bench/benchmark_jsonx_ints.nim` | `0.099198606s` | `30.25MiB` |

In this run, `jsonx` is about `2.57x` faster than `std/json`, `jsony` is about `2.39x` faster than `std/json`, and `eminim` is about `2.28x` faster than `std/json`. `jsonx` is about `1.08x` faster than `jsony`.

### OpenAI API-like file benchmark

This benchmark parses a generated chat-completions style payload (`bench/openai/openai_chat_payload.json`, ~75MiB, 60,000 sessions with message/tool-call/usage data) to better represent OpenAI API usage.

| Benchmark | Command | Time | Memory |
| --- | --- | --- | --- |
| `jsonx (openai)` | `nim c -d:danger -r bench/openai/benchmark_jsonx.nim` | `0.191892137s` (median of 3) | `0B` |
| `jsony (openai)` | `nim c -d:danger -r bench/openai/benchmark_jsony.nim` | `0.144781656s` (median of 3) | `0B` |

In this run, `jsony` is about `1.33x` faster than `jsonx` on the OpenAI API-like workload.
