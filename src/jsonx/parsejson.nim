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

import std/[strutils, unicode, parseutils]
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
    i: BiggestInt
    f: float
    tok*: TokKind
    filename: string
    rawStringLiterals: bool

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

proc getInt*(my: JsonParser): BiggestInt {.inline.} =
  ## returns the number for the last ``tkInt`` token.
  assert(my.tok == tkInt)
  result = my.i

proc getFloat*(my: JsonParser): float {.inline.} =
  ## returns the number for the last ``tkFloat`` token.
  assert(my.tok == tkFloat)
  result = my.f

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

proc addSpan(dst: var string; src: string; startPos, endPos: int) {.inline.} =
  let n = endPos - startPos
  if n <= 0:
    return
  let oldLen = dst.len
  setLen(dst, oldLen + n)
  copyMem(addr dst[oldLen], addr src[startPos], n)

when defined(jsonxRawParseInt):
  proc rawParseBiggestInt(s: openArray[char], b: var BiggestInt; start = 0): int {.inline.} =
    var
      sign: BiggestInt = -1
      i = start
    if i < s.len:
      if s[i] == '+':
        inc(i)
      elif s[i] == '-':
        inc(i)
        sign = 1

    if i < s.len and s[i] in {'0'..'9'}:
      b = 0
      while i < s.len and s[i] in {'0'..'9'}:
        let c = ord(s[i]) - ord('0')
        if b >= (low(BiggestInt) + c) div 10:
          b = b * 10 - c
        else:
          return 0
        inc(i)
        while i < s.len and s[i] == '_':
          inc(i) # underscores are allowed and ignored

      if sign == -1 and b == low(BiggestInt):
        return 0
      b = b * sign
      result = i - start
    else:
      result = 0

proc parseString(my: var JsonParser): TokKind =
  result = tkString
  var pos = my.bufpos + 1
  var spanStart = pos
  if my.rawStringLiterals:
    add(my.a, '"')
  while true:
    case my.buf[pos]
    of '\0':
      addSpan(my.a, my.buf, spanStart, pos)
      result = tkError
      break
    of '"':
      addSpan(my.a, my.buf, spanStart, pos)
      if my.rawStringLiterals:
        add(my.a, '"')
      inc(pos)
      break
    of '\\':
      addSpan(my.a, my.buf, spanStart, pos)
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
      spanStart = pos
    of '\c':
      addSpan(my.a, my.buf, spanStart, pos)
      pos = lexbase.handleCR(my, pos)
      add(my.a, '\c')
      spanStart = pos
    of '\L':
      addSpan(my.a, my.buf, spanStart, pos)
      pos = lexbase.handleLF(my, pos)
      add(my.a, '\L')
      spanStart = pos
    else:
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

proc parseNumberValue(my: var JsonParser; tokenStart, tokenLen: int;
    kind: TokKind): TokKind {.inline.} =
  var L = 0
  if kind == tkFloat:
    L = parseFloat(my.buf, my.f, tokenStart)
  else:
    when defined(jsonxRawParseInt):
      L = rawParseBiggestInt(my.buf, my.i, tokenStart)
    else:
      try:
        L = parseBiggestInt(my.buf, my.i, tokenStart)
      except ValueError:
        return tkError
  if L != tokenLen:
    return tkError
  result = kind

proc parseNumber(my: var JsonParser): TokKind {.inline.} =
  let tokenStart = my.bufpos
  var pos = tokenStart
  var hasDot = false
  var hasExp = false
  if my.buf[pos] == '-':
    inc(pos)
  if my.buf[pos] == '.':
    hasDot = true
    inc(pos)
  else:
    while my.buf[pos] in Digits:
      inc(pos)
    if my.buf[pos] == '.':
      hasDot = true
      inc(pos)
  while my.buf[pos] in Digits:
    inc(pos)
  if my.buf[pos] in {'E', 'e'}:
    hasExp = true
    inc(pos)
    if my.buf[pos] in {'+', '-'}:
      inc(pos)
    while my.buf[pos] in Digits:
      inc(pos)

  my.bufpos = pos
  result = if hasDot or hasExp: tkFloat else: tkInt
  result = parseNumberValue(my, tokenStart, pos - tokenStart, result)

proc parseKeyword(my: var JsonParser): TokKind =
  let pos = my.bufpos
  case my.buf[pos]
  of 'n':
    if my.buf[pos + 1] == 'u' and my.buf[pos + 2] == 'l' and
       my.buf[pos + 3] == 'l' and my.buf[pos + 4] notin IdentChars:
      my.bufpos = pos + 4
      return tkNull
  of 't':
    if my.buf[pos + 1] == 'r' and my.buf[pos + 2] == 'u' and
       my.buf[pos + 3] == 'e' and my.buf[pos + 4] notin IdentChars:
      my.bufpos = pos + 4
      return tkTrue
  of 'f':
    if my.buf[pos + 1] == 'a' and my.buf[pos + 2] == 'l' and
       my.buf[pos + 3] == 's' and my.buf[pos + 4] == 'e' and
       my.buf[pos + 5] notin IdentChars:
      my.bufpos = pos + 5
      return tkFalse
  else:
    discard

  var endPos = pos
  while my.buf[endPos] in IdentChars:
    inc(endPos)
  my.bufpos = endPos
  result = tkError

proc getTok*(my: var JsonParser): TokKind =
  setLen(my.a, 0)
  skip(my) # skip whitespace, comments
  case my.buf[my.bufpos]
  of '-', '.', '0'..'9':
    result = parseNumber(my)
  of '"':
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
    result = parseKeyword(my)
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
