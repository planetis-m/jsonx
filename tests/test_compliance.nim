import jsonx
import jsonx/parsejson

type
  DuplicateKeyObj = object
    a: int

proc expectReject[T](s: string; _: typedesc[T]) =
  doAssertRaises(JsonParsingError):
    discard fromJson(s, T)

proc expectAccept[T](s: string; _: typedesc[T]): T =
  result = fromJson(s, T)

block:
  # Valid number forms
  doAssert expectAccept("0", int) == 0
  doAssert expectAccept("-0", int) == 0
  doAssert expectAccept("0.0", float) == 0.0
  doAssert expectAccept("1e0", float) == 1.0
  doAssert expectAccept("1E-2", float) == 0.01

block:
  # Invalid number forms
  expectReject("01", int)
  expectReject("+1", int)
  expectReject("-", int)
  expectReject(".1", float)
  expectReject("1.", float)
  expectReject("1e", float)
  expectReject("1e+", float)
  expectReject("1e-", float)
  expectReject("NaN", float)
  expectReject("Infinity", float)
  expectReject("-Infinity", float)

block:
  # Structural strictness
  # Current jsonx behavior: trailing commas are accepted (non-standard extension).
  doAssert expectAccept("""[1,]""", seq[int]) == @[1]
  doAssert expectAccept("""{"a":1,}""", DuplicateKeyObj).a == 1
  expectReject("""{"a":1} {"a":2}""", DuplicateKeyObj)
  expectReject("// comment\n1", int)
  expectReject("/* comment */ 1", int)

block:
  # RFC whitespace only: space, tab, CR, LF
  doAssert expectAccept(" \t\r\n 1 \r\n\t ", int) == 1
  expectReject("\f1", int)

block:
  # String escapes
  let escaped = expectAccept(
    "\"\\\\\\\"\\/\\b\\f\\n\\r\\t\\u0041\"",
    string
  )
  doAssert escaped == "\\\"/\b\f\n\r\tA"

  let smile = expectAccept("\"\\uD83D\\uDE00\"", string)
  doAssert smile == "😀"

  # Current jsonx behavior: non-standard escapes are accepted.
  discard expectAccept("\"\\x\"", string)
  expectReject("\"\\u12\"", string)
  expectReject("\"\\uD800\"", string)

block:
  # Duplicate key policy: last value wins
  let x = expectAccept("""{"a":1,"a":2}""", DuplicateKeyObj)
  doAssert x.a == 2
