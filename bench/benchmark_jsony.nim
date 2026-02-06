## Benchmark jsony:

import std/[strutils, times]
import jsony

type
  Coordinate = object
    x: float
    y: float
    z: float

  BenchmarkInput = object
    coordinates: seq[Coordinate]

proc main =
  let payload = readFile("1.json")
  let jobj = fromJson(payload, BenchmarkInput)

  let coordinates = jobj.coordinates
  let len = float(coordinates.len)
  doAssert coordinates.len == 1_000_000
  var x = 0.0
  var y = 0.0
  var z = 0.0

  for coord in coordinates:
    x += coord.x
    y += coord.y
    z += coord.z

  echo x / len
  echo y / len
  echo z / len

let start = cpuTime()
main()
echo "used Mem: ", formatSize getOccupiedMem(), " time: ", cpuTime() - start, "s"
