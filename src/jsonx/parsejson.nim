#
#
#            Nim's Runtime Library
#        (c) Copyright 2018 Nim contributors
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module implements a json parser. It is used
## and exported by the `json` standard library
## module, but can also be used in its own right.

import std/[strutils, unicode]
import jsonx/[lexbase, streams]
import std/private/decode_helpers

when defined(nimPreviewSlimSystem):
  import std/assertions

type
  TokKind* = enum
    tkError,
    tkEof,
    tkString,
    tkInt,
    tkFloat,
    tkTrue,
    tkFalse,
    tkNull,
    tkCurlyLe,
    tkCurlyRi,
    tkBracketLe,
    tkBracketRi,
    tkColon,
    tkComma

  JsonParser* = object of BaseLexer ## the parser object.
    a*: string
    i: int64
    f: float
    giant: bool
    tok*: TokKind
    filename: string
    rawStringLiterals: bool

  JsonKindError* = object of ValueError ## raised by the `to` macro if the
                                        ## JSON kind is incorrect.
  JsonParsingError* = object of ValueError ## is raised for a JSON error

const
  tokToStr: array[TokKind, string] = [
    "invalid token",
    "EOF",
    "string literal",
    "int literal",
    "float literal",
    "true",
    "false",
    "null",
    "{", "}", "[", "]", ":", ","
  ]

proc open*(my: var JsonParser, input: Stream, filename: string;
           rawStringLiterals = false) =
  ## initializes the parser with an input stream. `Filename` is only used
  ## for nice error messages. If `rawStringLiterals` is true, string literals
  ## are kept with their surrounding quotes and escape sequences in them are
  ## left untouched too.
  lexbase.open(my, input)
  my.filename = filename
  my.a = ""
  my.rawStringLiterals = rawStringLiterals

proc close*(my: var JsonParser) {.inline.} =
  ## closes the parser `my` and its associated input stream.
  lexbase.close(my)

proc isGiant*(my: JsonParser): bool {.inline.} =
  ## returns whether the last ``tkInt|tkFloat`` token was too large for the fast path.
  assert(my.tok in {tkInt, tkFloat})
  my.giant

proc getInt*(my: JsonParser): BiggestInt {.inline.} =
  ## returns the number for the last ``tkInt`` token.
  assert(my.tok == tkInt)
  if my.giant: parseBiggestInt(my.a)
  else: cast[BiggestInt](my.i)

proc getFloat*(my: JsonParser): float {.inline.} =
  ## returns the number for the last ``tkFloat`` token.
  assert(my.tok == tkFloat)
  if my.giant: parseFloat(my.a)
  else: my.f

proc getColumn*(my: JsonParser): int {.inline.} =
  ## get the current column the parser has arrived at.
  result = getColNumber(my, my.bufpos)

proc getLine*(my: JsonParser): int {.inline.} =
  ## get the current line the parser has arrived at.
  result = my.lineNumber

proc getFilename*(my: JsonParser): string {.inline.} =
  ## get the filename of the file that the parser processes.
  result = my.filename

proc errorMsgExpected*(my: JsonParser, e: string): string =
  ## returns an error message "`e` expected" in the same format as the
  ## other error messages
  result = "$1($2, $3) Error: $4" % [
    my.filename, $getLine(my), $getColumn(my), e & " expected"]

proc parseEscapedUTF16*(buf: cstring, pos: var int): int =
  result = 0
  #UTF-16 escape is always 4 bytes.
  for _ in 0..3:
    # if char in '0' .. '9', 'a' .. 'f', 'A' .. 'F'
    if handleHexChar(buf[pos], result):
      inc(pos)
    else:
      return -1

proc parseString(my: var JsonParser): TokKind =
  result = tkString
  var pos = my.bufpos + 1
  if my.rawStringLiterals:
    add(my.a, '"')
  while true:
    case my.buf[pos]
    of '\0':
      result = tkError
      break
    of '"':
      if my.rawStringLiterals:
        add(my.a, '"')
      inc(pos)
      break
    of '\\':
      if my.rawStringLiterals:
        add(my.a, '\\')
      case my.buf[pos+1]
      of '\\', '"', '\'', '/':
        add(my.a, my.buf[pos+1])
        inc(pos, 2)
      of 'b':
        add(my.a, '\b')
        inc(pos, 2)
      of 'f':
        add(my.a, '\f')
        inc(pos, 2)
      of 'n':
        add(my.a, '\L')
        inc(pos, 2)
      of 'r':
        add(my.a, '\C')
        inc(pos, 2)
      of 't':
        add(my.a, '\t')
        inc(pos, 2)
      of 'v':
        add(my.a, '\v')
        inc(pos, 2)
      of 'u':
        if my.rawStringLiterals:
          add(my.a, 'u')
        inc(pos, 2)
        var pos2 = pos
        var r = parseEscapedUTF16(cstring(my.buf), pos)
        if r < 0:
          break
        # Deal with surrogates
        if (r and 0xfc00) == 0xd800:
          if my.buf[pos] != '\\' or my.buf[pos+1] != 'u':
            break
          inc(pos, 2)
          var s = parseEscapedUTF16(cstring(my.buf), pos)
          if (s and 0xfc00) == 0xdc00 and s > 0:
            r = 0x10000 + (((r - 0xd800) shl 10) or (s - 0xdc00))
          else:
            break
        if my.rawStringLiterals:
          let length = pos - pos2
          for i in 1 .. length:
            if my.buf[pos2] in {'0'..'9', 'A'..'F', 'a'..'f'}:
              add(my.a, my.buf[pos2])
              inc pos2
            else:
              break
        else:
          add(my.a, toUTF8(Rune(r)))
      else:
        # don't bother with the error
        add(my.a, my.buf[pos])
        inc(pos)
    of '\c':
      pos = lexbase.handleCR(my, pos)
      add(my.a, '\c')
    of '\L':
      pos = lexbase.handleLF(my, pos)
      add(my.a, '\L')
    else:
      add(my.a, my.buf[pos])
      inc(pos)
  my.bufpos = pos # store back

proc skip(my: var JsonParser) =
  var pos = my.bufpos
  while true:
    case my.buf[pos]
    of ' ', '\t':
      inc(pos)
    of '\c':
      pos = lexbase.handleCR(my, pos)
    of '\L':
      pos = lexbase.handleLF(my, pos)
    else:
      break
  my.bufpos = pos

template doCopy(a, b, startPos, endPos: untyped): untyped =
  let n = endPos - startPos
  if n > 0:
    a.setLen n
    copyMem a[0].addr, b[startPos].addr, n

proc i64(c: char): int64 {.inline.} = int64(ord(c) - ord('0'))

proc pow10(e: int64): float {.inline.} =
  const p10 = [1e-22, 1e-21, 1e-20, 1e-19, 1e-18, 1e-17, 1e-16, 1e-15, 1e-14,
               1e-13, 1e-12, 1e-11, 1e-10, 1e-09, 1e-08, 1e-07, 1e-06, 1e-05,
               1e-4, 1e-3, 1e-2, 1e-1, 1.0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7,
               1e8, 1e9]
  if -22 <= e and e <= 9:
    return p10[e + 22]
  result = 1.0
  var base = 10.0
  var e = e
  if e < 0:
    e = -e
    base = 0.1
  while e != 0:
    if (e and 1) != 0:
      result *= base
    e = e shr 1
    base *= base

proc parseNumber(my: var JsonParser): TokKind {.inline.} =
  let startPos = my.bufpos
  const Sign = {'+', '-'}
  var i = startPos
  var noDot = false
  var exp = 0'i64
  var p10 = 0
  var pnt = -1
  var nD = 0
  var digits = 0
  my.giant = false
  my.i = 0'i64
  if my.buf[i] in Sign:
    i.inc
  let intStart = i
  while my.buf[i] != '\0':
    if my.buf[i] notin Digits:
      if my.buf[i] != '.' or pnt >= 0:
        break
      pnt = nD
      nD.dec
    elif nD < 18:
      my.i = 10 * my.i + my.buf[i].i64
      digits.inc
    else:
      my.giant = true
      p10.inc
      digits.inc
    i.inc
    nD.inc
  if digits == 0:
    return tkError
  if my.buf[intStart] == '0' and nD > 1 and pnt != 1:
    return tkError
  if my.buf[startPos] == '-':
    my.i = -my.i
  if pnt < 0:
    pnt = nD
    noDot = true
  elif nD == 1:
    return tkError
  if my.buf[i] in {'E', 'e'}:
    i.inc
    let i0 = i
    if my.buf[i] in Sign:
      i.inc
    let expStart = i
    while my.buf[i] in Digits:
      exp = 10 * exp + my.buf[i].i64
      i.inc
    if i == expStart:
      return tkError
    if my.buf[i0] == '-':
      exp = -exp
  elif noDot:
    my.bufpos = i
    if my.giant:
      doCopy(my.a, my.buf, startPos, i)
    return tkInt
  exp += pnt - nD + p10
  my.f = my.i.float * pow10(exp)
  if my.giant:
    doCopy(my.a, my.buf, startPos, i)
  my.bufpos = i
  return tkFloat

proc parseName(my: var JsonParser) =
  var pos = my.bufpos
  if my.buf[pos] in IdentStartChars:
    while my.buf[pos] in IdentChars:
      add(my.a, my.buf[pos])
      inc(pos)
  my.bufpos = pos

proc getTok*(my: var JsonParser): TokKind =
  skip(my) # skip whitespace, comments
  case my.buf[my.bufpos]
  of '-', '.', '0'..'9':
    setLen(my.a, 0)
    result = parseNumber(my)
  of '"':
    setLen(my.a, 0)
    result = parseString(my)
  of '[':
    inc(my.bufpos)
    result = tkBracketLe
  of '{':
    inc(my.bufpos)
    result = tkCurlyLe
  of ']':
    inc(my.bufpos)
    result = tkBracketRi
  of '}':
    inc(my.bufpos)
    result = tkCurlyRi
  of ',':
    inc(my.bufpos)
    result = tkComma
  of ':':
    inc(my.bufpos)
    result = tkColon
  of '\0':
    result = tkEof
  of 'a'..'z', 'A'..'Z', '_':
    setLen(my.a, 0)
    parseName(my)
    case my.a
    of "null": result = tkNull
    of "true": result = tkTrue
    of "false": result = tkFalse
    else: result = tkError
  else:
    inc(my.bufpos)
    result = tkError
  my.tok = result


proc raiseParseErr*(p: JsonParser, msg: string) {.noinline, noreturn.} =
  ## raises an `EJsonParsingError` exception.
  raise newException(JsonParsingError, errorMsgExpected(p, msg))

proc eat*(p: var JsonParser, tok: TokKind) =
  if p.tok == tok: discard getTok(p)
  else: raiseParseErr(p, tokToStr[tok])
