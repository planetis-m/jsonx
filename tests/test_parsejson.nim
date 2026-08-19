import jsonx/streams
import jsonx/parsejson

proc tokens(input: string): seq[TokKind] =
  var p: parsejson.JsonParser
  let s = streams.open(input)
  open(p, s, "test.json")
  defer:
    close(p)
  while true:
    let tk = getTok(p)
    result.add(tk)
    if tk in {tkEof, tkError}:
      break

when isMainModule:
  let toks = tokens("""{"a": 1, "b": [true, null, "x"], "c": 3.5}""")
  doAssert toks.len > 0
  doAssert toks[0] == tkCurlyLe
  doAssert toks[^1] == tkEof

  let toks2 = tokens("""[0, -1, 2.5, 6.02e23, -4E-2]""")
  doAssert tkBracketLe in toks2
  doAssert tkInt in toks2
  doAssert tkFloat in toks2
  doAssert toks2[^1] == tkEof

  let toks3 = tokens(" \t\r\ntrue  false null ")
  doAssert toks3.len >= 4
  doAssert toks3[0] == tkTrue
  doAssert toks3[1] == tkFalse
  doAssert toks3[2] == tkNull
  doAssert toks3[^1] == tkEof

  let toks4 = tokens("\"line\\nsep\"")
  doAssert toks4[0] == tkString
  doAssert toks4[^1] == tkEof

  let toks5 = tokens("{\"u\":\"\\u0041\\u03B1\"}")
  doAssert toks5[0] == tkCurlyLe
  doAssert toks5[^1] == tkEof

  let toks6 = tokens("{\"bad\": \"\\uD800\"}")
  doAssert tkError in toks6

  let toks7 = tokens("// comment\n1")
  doAssert tkError in toks7

  let toks8 = tokens("\x01true")
  doAssert toks8[0] == tkError
