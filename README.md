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

Iterate array items:

```nim
import jsonx
import jsonx/streams

let s = streams.open("[{\"name\":\"A\"},{\"name\":\"B\"}]")
for item in jsonItems(s, Person):
  discard
```

## Tests

Run from the repo root:

```sh
nim c -r tests/test.nim
nim c -r tests/test_parsejson.nim
```
