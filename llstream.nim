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
  TLLStreamKind* = enum
    llsNone,
    llsString,
    llsFile

  TLLStream* = object of RootObj
    kind*: TLLStreamKind
    f*: File
    s*: string
    rd*: int

  PLLStream* = ref TLLStream

proc llStreamOpen*(data: sink string): PLLStream =
  PLLStream(kind: llsString, s: data)

proc llStreamOpen*(f: File): PLLStream =
  PLLStream(kind: llsFile, f: f)

proc llStreamOpen*(): PLLStream =
  PLLStream(kind: llsNone)

proc llStreamClose*(s: PLLStream) =
  case s.kind
  of llsNone, llsString:
    discard
  of llsFile:
    close(s.f)

proc llStreamRead*(s: PLLStream, buf: pointer, bufLen: int): int =
  case s.kind
  of llsNone:
    result = 0
  of llsString:
    result = min(bufLen, s.s.len - s.rd)
    if result > 0:
      copyMem(buf, addr(s.s[s.rd]), result)
      inc(s.rd, result)
  of llsFile:
    result = readBuffer(s.f, buf, bufLen)

proc llStreamWrite*(s: PLLStream, data: string) =
  case s.kind
  of llsNone:
    discard
  of llsString:
    s.s.add(data)
  of llsFile:
    write(s.f, data)

proc llStreamWriteln*(s: PLLStream, data: string) =
  llStreamWrite(s, data)
  llStreamWrite(s, "\n")

proc llStreamWrite*(s: PLLStream, data: char) =
  var c: char
  case s.kind
  of llsNone:
    discard
  of llsString:
    s.s.add(data)
  of llsFile:
    c = data
    discard writeBuffer(s.f, addr(c), sizeof(c))

proc llStreamWrite*(s: PLLStream, buf: pointer, buflen: int) =
  case s.kind
  of llsNone:
    discard
  of llsString:
    if buflen > 0:
      let start = s.s.len
      s.s.setLen(start + buflen)
      copyMem(addr s.s[start], buf, buflen)
  of llsFile:
    if buflen > 0:
      discard writeBuffer(s.f, buf, buflen)

proc llStreamReadAll*(s: PLLStream): string =
  result = ""
  var buf: array[4096, char]
  while true:
    let n = llStreamRead(s, addr buf[0], buf.len)
    if n <= 0:
      break
    result.setLen(result.len + n)
    copyMem(addr result[^n], addr buf[0], n)
