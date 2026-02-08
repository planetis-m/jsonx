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
    tokenStart: int
    tokenLen: int
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
  my.tokenStart = 0
  my.tokenLen = 0
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

proc parseString(my: var JsonParser): TokKind =
  result = tkString
  let quotePos = my.bufpos
  var pos = quotePos + 1

  while true:
    case my.buf[pos]
    of '\0':
      result = tkError
      break
    of '"':
      inc(pos)
      break
    of '\\':
      case my.buf[pos + 1]
      of '\0':
        result = tkError
        break
      of '\\', '"', '\'', '/', 'b', 'f', 'n', 'r', 't', 'v':
        inc(pos, 2)
      of 'u':
        inc(pos, 2)
        var r = parseEscapedUTF16(cstring(my.buf), pos)
        if r < 0:
          result = tkError
          break
        # Validate UTF-16 surrogate pairs while tokenizing.
        if (r and 0xfc00) == 0xd800:
          if my.buf[pos] != '\\' or my.buf[pos + 1] != 'u':
            result = tkError
            break
          inc(pos, 2)
          let s = parseEscapedUTF16(cstring(my.buf), pos)
          if not ((s and 0xfc00) == 0xdc00 and s > 0):
            result = tkError
            break
      else:
        # Keep legacy behavior for unknown escapes.
        inc(pos)
    of '\c', '\L':
      result = tkError
      break
    else:
      inc(pos)

  if result == tkString:
    if my.rawStringLiterals:
      my.tokenStart = quotePos
      my.tokenLen = pos - quotePos
    else:
      my.tokenStart = quotePos + 1
      my.tokenLen = pos - quotePos - 2
  my.bufpos = pos # store back

proc getString*(my: JsonParser): string {.inline.} =
  ## returns the string literal for the last ``tkString`` token.
  assert(my.tok == tkString)
  if my.tokenLen <= 0:
    result = ""
  elif my.rawStringLiterals:
    result = my.buf.substr(my.tokenStart, my.tokenStart + my.tokenLen - 1)
  else:
    var pos = my.tokenStart
    let tokenEnd = my.tokenStart + my.tokenLen
    while pos < tokenEnd:
      if my.buf[pos] != '\\':
        add(result, my.buf[pos])
        inc(pos)
      else:
        case my.buf[pos + 1]
        of '\\', '"', '\'', '/':
          add(result, my.buf[pos + 1])
          inc(pos, 2)
        of 'b':
          add(result, '\b')
          inc(pos, 2)
        of 'f':
          add(result, '\f')
          inc(pos, 2)
        of 'n':
          add(result, '\L')
          inc(pos, 2)
        of 'r':
          add(result, '\C')
          inc(pos, 2)
        of 't':
          add(result, '\t')
          inc(pos, 2)
        of 'v':
          add(result, '\v')
          inc(pos, 2)
        of 'u':
          inc(pos, 2)
          var r = parseEscapedUTF16(cstring(my.buf), pos)
          # parseString validates paired surrogates for us.
          if (r and 0xfc00) == 0xd800:
            inc(pos, 2) # skip '\u'
            let s = parseEscapedUTF16(cstring(my.buf), pos)
            r = 0x10000 + (((r - 0xd800) shl 10) or (s - 0xdc00))
          add(result, toUTF8(Rune(r)))
        else:
          add(result, '\\')
          inc(pos)

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
  my.tokenStart = my.bufpos
  my.tokenLen = 0
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
