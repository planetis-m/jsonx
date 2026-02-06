import std/math
import jsonx
import jsonx/parsejson

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
  doAssert almostEq(a, b)
  doAssert almostEq(b, c)

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
  doAssertRaises(JsonParsingError):
    discard fromJson("01", int)
  doAssertRaises(JsonParsingError):
    discard fromJson("1e", float)
  doAssertRaises(JsonParsingError):
    discard fromJson("+1", int)
  doAssertRaises(JsonParsingError):
    discard fromJson("--1", int)
