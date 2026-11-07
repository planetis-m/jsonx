## Benchmark brian:

import std/[strutils, times]
import brian

type
  Coordinate = object
    x: float
    y: float
    z: float

  BenchmarkInput = object
    coordinates: seq[Coordinate]

proc main() =
  let payload = readFile("1.json")
  let jobj = fromJson(payload, BenchmarkInput)

  let coordinates = jobj.coordinates
  let length = float(coordinates.len)
  doAssert coordinates.len == 1_000_000
  var x = 0.0
  var y = 0.0
  var z = 0.0

  for coordinate in coordinates:
    x += coordinate.x
    y += coordinate.y
    z += coordinate.z

  echo x / length
  echo y / length
  echo z / length

let start = cpuTime()
main()
echo "used Mem: ", formatSize(getOccupiedMem()), " time: ", cpuTime() - start, "s"
