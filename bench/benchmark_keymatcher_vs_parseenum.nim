## Benchmark keymatcher vs strutils.parseEnum on string-to-enum mapping.

import std/[algorithm, strutils, times]
import jsonx/keymatcher

type
  BenchKey = enum
    UnknownKey
    k00, k01, k02, k03, k04, k05, k06, k07
    k08, k09, k10, k11, k12, k13, k14, k15
    k16, k17, k18, k19, k20, k21, k22, k23
    k24, k25, k26, k27, k28, k29, k30, k31

declareMatcher matchBenchKey, BenchKey, ord(k00)

const Inputs = [
  "k00", "k01", "k02", "k03", "k04", "k05", "k06", "k07",
  "k08", "k09", "k10", "k11", "k12", "k13", "k14", "k15",
  "k16", "k17", "k18", "k19", "k20", "k21", "k22", "k23",
  "k24", "k25", "k26", "k27", "k28", "k29", "k30", "k31"
]

proc runParseEnum(rounds: int): tuple[seconds: float, checksum: int] =
  var checksum = 0
  let start = cpuTime()
  for _ in 0..<rounds:
    for s in Inputs:
      checksum = checksum xor ord(parseEnum[BenchKey](s))
  result = (cpuTime() - start, checksum)

proc runKeyMatcher(rounds: int): tuple[seconds: float, checksum: int] =
  var checksum = 0
  let start = cpuTime()
  for _ in 0..<rounds:
    for s in Inputs:
      checksum = checksum xor ord(matchBenchKey(s))
  result = (cpuTime() - start, checksum)

proc median(xs: seq[float]): float =
  var tmp = xs
  tmp.sort()
  result = tmp[tmp.len div 2]

proc main() =
  const Trials = 7
  const Rounds = 300_000
  let lookups = float(Rounds * Inputs.len)

  # Warmup to reduce first-run noise.
  discard runParseEnum(5_000)
  discard runKeyMatcher(5_000)

  var parseTimes: seq[float] = @[]
  var matcherTimes: seq[float] = @[]
  var parseChecksum = 0
  var matcherChecksum = 0

  for trial in 0..<Trials:
    if (trial and 1) == 0:
      let p = runParseEnum(Rounds)
      parseTimes.add p.seconds
      parseChecksum = parseChecksum xor p.checksum
      let m = runKeyMatcher(Rounds)
      matcherTimes.add m.seconds
      matcherChecksum = matcherChecksum xor m.checksum
    else:
      let m = runKeyMatcher(Rounds)
      matcherTimes.add m.seconds
      matcherChecksum = matcherChecksum xor m.checksum
      let p = runParseEnum(Rounds)
      parseTimes.add p.seconds
      parseChecksum = parseChecksum xor p.checksum

  doAssert parseChecksum == matcherChecksum

  let parseMedian = median(parseTimes)
  let matcherMedian = median(matcherTimes)
  let parseNs = parseMedian * 1e9 / lookups
  let matcherNs = matcherMedian * 1e9 / lookups

  echo "lookups per trial: ", int(lookups)
  echo "parseEnum median: ", parseMedian, "s (", parseNs, " ns/lookup)"
  echo "keymatcher median: ", matcherMedian, "s (", matcherNs, " ns/lookup)"

  if matcherMedian < parseMedian:
    echo "winner: keymatcher (", parseMedian / matcherMedian, "x faster)"
  elif parseMedian < matcherMedian:
    echo "winner: parseEnum (", matcherMedian / parseMedian, "x faster)"
  else:
    echo "winner: tie"

when isMainModule:
  main()
