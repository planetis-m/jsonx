#
#
#           The Nim Compiler
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Minimal low-level streams for lexbase/parsejson.
## Only the required pieces are kept.

type
  StreamKind* = enum
    skNone,
    skString,
    skFile

  Stream* = ref object of RootObj
    kind*: StreamKind
    f*: File
    s*: string
    rd*: int

proc open*(data: sink string): Stream =
  Stream(kind: skString, s: data)

proc open*(f: File): Stream =
  Stream(kind: skFile, f: f)

proc open*(): Stream =
  Stream(kind: skNone)

proc close*(s: Stream) =
  case s.kind
  of skNone, skString:
    discard
  of skFile:
    close(s.f)

proc read*(s: Stream, buf: pointer, bufLen: int): int =
  case s.kind
  of skNone:
    result = 0
  of skString:
    result = min(bufLen, s.s.len - s.rd)
    if result > 0:
      copyMem(buf, addr(s.s[s.rd]), result)
      inc(s.rd, result)
  of skFile:
    result = readBuffer(s.f, buf, bufLen)

proc write*(s: Stream, data: string) =
  case s.kind
  of skNone:
    discard
  of skString:
    s.s.add(data)
  of skFile:
    write(s.f, data)

proc writeln*(s: Stream, data: string) =
  write(s, data)
  write(s, "\n")

proc write*(s: Stream, data: char) =
  var c: char
  case s.kind
  of skNone:
    discard
  of skString:
    s.s.add(data)
  of skFile:
    c = data
    discard writeBuffer(s.f, addr(c), sizeof(c))

proc write*(s: Stream, buf: pointer, buflen: int) =
  case s.kind
  of skNone:
    discard
  of skString:
    if buflen > 0:
      let start = s.s.len
      s.s.setLen(start + buflen)
      copyMem(addr s.s[start], buf, buflen)
  of skFile:
    if buflen > 0:
      discard writeBuffer(s.f, buf, buflen)

proc readAll*(s: Stream): string =
  result = ""
  var buf: array[4096, char]
  while true:
    let n = read(s, addr buf[0], buf.len)
    if n <= 0:
      break
    result.setLen(result.len + n)
    copyMem(addr result[^n], addr buf[0], n)
