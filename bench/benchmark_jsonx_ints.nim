## Benchmark jsonx (int-heavy):

{.define: jsonxLenient.}

import std/[strutils, times]
import jsonx

type
  BenchmarkInput = object
    values: seq[int64]

proc makePayload(n: int): string =
  result = newStringOfCap(32 + n * 21)
  result.add("{\"values\":[")
  for i in 0..<n:
    if i > 0:
      result.add(',')
    # 19-digit ints force the giant-int path while remaining valid int64.
    if (i and 1) == 0:
      result.add("1234567890123456789")
    else:
      result.add("9223372036854775807")
  result.add("]}")

let payload = makePayload(1_000_000)
let start = cpuTime()
let jobj = fromJson(payload, BenchmarkInput)
let elapsed = cpuTime() - start

doAssert jobj.values.len == 1_000_000
echo jobj.values[0] xor jobj.values[^1]
echo "used Mem: ", formatSize getOccupiedMem(), " time: ", elapsed, "s"
