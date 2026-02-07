import std/[math, strutils]
import jsonx
import jsonx/parsejson
import jsonx/streams

type
  NumberPayload = object
    i: int64
    neg: int
    x: float
    y: float
    z: float
    t: float

proc almostEq(a, b: float; relEps = 1e-12): bool =
  let scale = max(1.0, max(abs(a), abs(b)))
  result = abs(a - b) <= relEps * scale

proc expectReject[T](s: string; _: typedesc[T]) =
  doAssertRaises(JsonParsingError):
    discard fromJson(s, T)

proc lexNumber(input: string): (TokKind, bool) =
  var p: JsonParser
  let s = streams.open(input)
  open(p, s, "test_numbers.json")
  defer: close(p)
  let tk = getTok(p)
  doAssert tk in {tkInt, tkFloat}, "expected numeric token for " & input
  result = (tk, isGiant(p))
  doAssert getTok(p) == tkEof, "expected eof for " & input

block:
  let payload = fromJson(
    """{"i":922337203685477580,"neg":-42,"x":3.5,"y":6.02e23,"z":-4E-2,"t":0.30000000000000004}""",
    NumberPayload
  )
  doAssert payload.i == 922337203685477580'i64
  doAssert payload.neg == -42
  doAssert almostEq(payload.x, 3.5)
  doAssert almostEq(payload.y, 6.02e23)
  doAssert almostEq(payload.z, -0.04)
  doAssert almostEq(payload.t, 0.30000000000000004)

block:
  let a = fromJson("1.0", float)
  let b = fromJson("1e0", float)
  let c = fromJson("1E+0", float)
  let d = fromJson("1.2300e2", float)
  doAssert almostEq(a, b)
  doAssert almostEq(b, c)
  doAssert almostEq(d, 123.0)

block:
  for item in [
    ("0", 0'i64),
    ("-0", 0'i64),
    ("7", 7'i64),
    ("-7", -7'i64),
    ("10", 10'i64),
    ("-10", -10'i64),
    ("9223372036854775807", high(int64)),
    ("-9223372036854775808", low(int64))
  ]:
    let (s, expected) = item
    doAssert fromJson(s, int64) == expected

block:
  for item in [
    ("0.0", 0.0),
    ("-0.0", -0.0),
    ("3.141592653589793", 3.141592653589793),
    ("6.02214076e23", 6.02214076e23),
    ("1E-2", 1e-2),
    ("1e-0", 1.0),
    ("1e+3", 1000.0),
    ("-4E-2", -0.04),
    ("0.30000000000000004", 0.30000000000000004)
  ]:
    let (s, expected) = item
    doAssert almostEq(fromJson(s, float), expected), s

block:
  let original = NumberPayload(
    i: 77'i64,
    neg: -9,
    x: 0.125,
    y: 9.99e6,
    z: -3.75e-4,
    t: 1.0 / 3.0
  )
  let encoded = toJson(original)
  let decoded = fromJson(encoded, NumberPayload)
  doAssert decoded.i == original.i
  doAssert decoded.neg == original.neg
  doAssert almostEq(decoded.x, original.x)
  doAssert almostEq(decoded.y, original.y)
  doAssert almostEq(decoded.z, original.z)
  doAssert almostEq(decoded.t, original.t)

block:
  for bad in [
    "01", "-01", "00", "00.1", "01.0",
    "+1", "--1", "-", "1.", "-1.", ".1", "-.1",
    "1e", "1e+", "1e-", "1e+-1", "1E--1",
    "1..0", "1.0.0", "1e1.2",
    "NaN", "Infinity", "-Infinity",
    "1x", "1.0x", "1e2x"
  ]:
    expectReject(bad, float)

block:
  let (tk18, giant18) = lexNumber("123456789012345678")
  doAssert tk18 == tkInt
  doAssert not giant18

  let (tk19, giant19) = lexNumber("1234567890123456789")
  doAssert tk19 == tkInt
  doAssert giant19

  let (tkBigFloat, giantBigFloat) = lexNumber("0." & "1".repeat(40))
  doAssert tkBigFloat == tkFloat
  doAssert giantBigFloat

  let (tkBigExpFloat, giantBigExpFloat) = lexNumber("9" & "0".repeat(40) & "e-5")
  doAssert tkBigExpFloat == tkFloat
  doAssert giantBigExpFloat
