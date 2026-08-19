import std/[algorithm, enumutils, hashes, macros, math, strutils, options, tables, sets, paths]
import jsonx/[parsejson, streams]
from std/typetraits import isNamedTuple, distinctBase, HoleyEnum

type
  UnknownFieldPolicy* = enum ## Controls unknown object fields during deserialization.
    ufSkip ## Skip object fields that do not exist in the target type.
    ufReject ## Reject object fields that do not exist in the target type.
  RawJson* = distinct string
  CanonRawJson* = distinct string
  RawJsonField = tuple[key: string, value: string]

proc `==`*(a, b: CanonRawJson): bool {.borrow.}
proc hash*(x: CanonRawJson): Hash {.borrow.}
proc `$`*(x: RawJson): string {.borrow.}
proc `$`*(x: CanonRawJson): string {.borrow.}

# serialization
proc escapeJsonUnquoted(x: string; dst: var string) =
  for c in x:
    case c
    of '\L': dst.add("\\n")
    of '\b': dst.add("\\b")
    of '\f': dst.add("\\f")
    of '\t': dst.add("\\t")
    of '\v': dst.add("\\u000b")
    of '\r': dst.add("\\r")
    of '"': dst.add("\\\"")
    of '\0'..'\7': dst.add("\\u000" & $ord(c))
    of '\14'..'\31': dst.add("\\u00" & toHex(ord(c), 2))
    of '\\': dst.add("\\\\")
    else: dst.add(c)

proc escapeJson*(s: string; dst: var string) =
  ## Converts a string `s` to its JSON representation with quotes.
  ## Appends to `result`.
  var hasEscape = false
  for c in s:
    if c <= '\31' or c == '"' or c == '\\':
      hasEscape = true
      break
  dst.add('"')
  if hasEscape:
    escapeJsonUnquoted(s, dst)
  else:
    dst.add(s)
  dst.add('"')

proc escapeJson*(s: Stream; x: string) =
  ## Converts a string `s` to its JSON representation with quotes.
  ## Appends to ``result``.
  var tmp = newStringOfCap(x.len + x.len shr 3)
  escapeJson(x, tmp)
  streams.write(s, tmp)

proc writeJsonNull*(s: Stream) =
  ## Creates a new JNull.
  streams.write(s, "null")

proc writeJson*(s: Stream; x: string) =
  ## Creates a new JString.
  escapeJson(s, x)

proc writeJson*(s: Stream; x: RawJson) =
  streams.write(s, string(x))

proc writeJson*(s: Stream; x: CanonRawJson) =
  streams.write(s, string(x))

proc writeJson*(s: Stream; b: bool) =
  ## Creates a new JBool.
  streams.write(s, if b: "true" else: "false")

proc writeJson*(s: Stream; n: BiggestInt) =
  ## Creates a new JInt.
  streams.write(s, $n)

proc writeJson*(s: Stream; n: float) =
  ## Creates a new JFloat.
  if n != n or n == Inf or n == NegInf:
    raise newException(ValueError, "cannot serialize non-finite float as JSON")
  streams.write(s, $n)

proc writeJson*(s: Stream; o: enum) =
  ## Construct a Json that represents the specified enum value as a
  ## string. Creates a new JString.
  writeJson(s, $o)

proc writeJson*[T](s: Stream; elements: openArray[T]) =
  ## Generic constructor for JSON data. Creates a new JArray.
  var comma = false
  streams.write(s, '[')
  for elem in elements:
    if comma: streams.write(s, ',')
    else: comma = true
    writeJson(s, elem)
  streams.write(s, ']')

proc writeJson*[T](s: Stream; o: SomeSet[T]|set[T]) =
  var comma = false
  streams.write(s, '[')
  for elem in o.items:
    if comma: streams.write(s, ',')
    else: comma = true
    writeJson(s, elem)
  streams.write(s, ']')

proc writeJson*[T](s: Stream; o: (Table[string, T]|OrderedTable[string, T])) =
  var comma = false
  streams.write(s, '{')
  for k, v in o.pairs:
    if comma: streams.write(s, ',')
    else: comma = true
    escapeJson(s, k)
    streams.write(s, ':')
    writeJson(s, v)
  streams.write(s, '}')

proc writeJson*[T](s: Stream; o: ref T) =
  if o.isNil:
    s.writeJsonNull()
  else:
    writeJson(s, o[])

proc writeJson*[T](s: Stream; o: Option[T]) =
  if isSome(o):
    writeJson(s, get(o))
  else:
    s.writeJsonNull()

proc writeJson*[T: tuple](s: Stream; o: T) =
  ## Generic constructor for JSON data. Creates a new JObject/JArray.
  when isNamedTuple(T):
    var comma = false
    streams.write(s, '{')
    for k, v in o.fieldPairs:
      if comma: streams.write(s, ',')
      else: comma = true
      escapeJson(s, k)
      streams.write(s, ':')
      writeJson(s, v)
    streams.write(s, '}')
  else:
    var comma = false
    streams.write(s, '[')
    for v in o.fields:
      if comma: streams.write(s, ',')
      else: comma = true
      writeJson(s, v)
    streams.write(s, ']')

proc writeJson*[T: object](s: Stream; o: T) =
  ## Generic constructor for JSON data. Creates a new JObject
  var comma = false
  streams.write(s, '{')
  for k, v in o.fieldPairs:
    if comma: streams.write(s, ',')
    else: comma = true
    escapeJson(s, k)
    streams.write(s, ':')
    writeJson(s, v)
  streams.write(s, '}')

# deserialization
template expectObjectSeparator*(p: JsonParser) =
  if p.tok == tkComma:
    discard getTok(p)
    if p.tok == tkCurlyRi:
      raiseParseErr(p, "string literal as key")
  elif p.tok != tkCurlyRi:
    raiseParseErr(p, "'}' or ','")

template expectArraySeparator*(p: JsonParser) =
  if p.tok == tkComma:
    discard getTok(p)
    if p.tok == tkBracketRi:
      raiseParseErr(p, "array element")
  elif p.tok != tkBracketRi:
    raiseParseErr(p, "']' or ','")

proc cmpRawJsonField(field: RawJsonField; key: string): int =
  result = cmp(field.key, key)

proc fitsIntType[T: SomeInteger](n: BiggestInt): bool =
  when T is SomeUnsignedInt:
    when sizeof(T) < sizeof(BiggestInt):
      result = n >= 0 and n <= BiggestInt(high(T))
    else:
      result = n >= 0
  else:
    when sizeof(T) < sizeof(BiggestInt):
      result = n >= BiggestInt(low(T)) and n <= BiggestInt(high(T))
    else:
      result = true

proc parseEnumValue[T: enum](n: BiggestInt; dst: var T): bool =
  result = false
  when T is HoleyEnum:
    for value in enumutils.items(T):
      if ord(value) == n:
        dst = value
        return true
  else:
    if n >= BiggestInt(ord(low(T))) and n <= BiggestInt(ord(high(T))):
      dst = T(n)
      result = true

proc writeParsedJson(dst: var string; p: var JsonParser; normalized: static[bool])

proc writeObjectJson(dst: var string; p: var JsonParser) =
  var comma = false
  dst.add('{')
  discard getTok(p)
  while p.tok != tkCurlyRi:
    if p.tok != tkString:
      raiseParseErr(p, "string literal as key")
    if comma: dst.add(',')
    else: comma = true
    escapeJson(p.a, dst)
    discard getTok(p)
    eat(p, tkColon)
    dst.add(':')
    writeParsedJson(dst, p, normalized = false)
    expectObjectSeparator(p)
  eat(p, tkCurlyRi)
  dst.add('}')

proc writeNormalizedObjectJson(dst: var string; p: var JsonParser) =
  var fields: seq[RawJsonField]
  discard getTok(p)
  while p.tok != tkCurlyRi:
    if p.tok != tkString:
      raiseParseErr(p, "string literal as key")
    let key = p.a
    discard getTok(p)
    eat(p, tkColon)
    var value = ""
    writeParsedJson(value, p, normalized = true)
    let idx = lowerBound(fields, key, cmpRawJsonField)
    if idx < fields.len and fields[idx].key == key:
      fields[idx].value = ensureMove(value)
    else:
      fields.insert((key, ensureMove(value)), idx)
    expectObjectSeparator(p)
  eat(p, tkCurlyRi)
  var comma = false
  dst.add('{')
  for field in fields:
    if comma: dst.add(',')
    else: comma = true
    escapeJson(field.key, dst)
    dst.add(':')
    dst.add(field.value)
  dst.add('}')

proc writeParsedJson(dst: var string; p: var JsonParser; normalized: static[bool]) =
  case p.tok
  of tkString:
    escapeJson(p.a, dst)
    discard getTok(p)
  of tkInt:
    dst.add($p.getInt())
    discard getTok(p)
  of tkFloat:
    dst.add($p.getFloat())
    discard getTok(p)
  of tkTrue:
    dst.add("true")
    discard getTok(p)
  of tkFalse:
    dst.add("false")
    discard getTok(p)
  of tkNull:
    dst.add("null")
    discard getTok(p)
  of tkCurlyLe:
    when normalized:
      writeNormalizedObjectJson(dst, p)
    else:
      writeObjectJson(dst, p)
  of tkBracketLe:
    var comma = false
    dst.add('[')
    discard getTok(p)
    while p.tok != tkBracketRi:
      if comma: dst.add(',')
      else: comma = true
      writeParsedJson(dst, p, normalized)
      expectArraySeparator(p)
    eat(p, tkBracketRi)
    dst.add(']')
  of tkError, tkNumberError, tkCurlyRi, tkBracketRi, tkColon, tkComma, tkEof:
    raiseParseErr(p, "JSON value")

proc appendRawJson*(dst: var string; p: var JsonParser) =
  ## Appends the current JSON value in the representation used by `RawJson`.
  ## Consumes that value from `p`.
  writeParsedJson(dst, p, normalized = false)

proc readJson*(dst: var string; p: var JsonParser; unknownFields: UnknownFieldPolicy) =
  if p.tok == tkNull:
    dst = ""
    discard getTok(p)
  elif p.tok == tkString:
    dst = p.a
    discard getTok(p)
  else:
    raiseParseErr(p, "string or null")

proc readJson*(dst: var RawJson; p: var JsonParser; unknownFields: UnknownFieldPolicy) =
  var tmp = ""
  appendRawJson(tmp, p)
  dst = RawJson(ensureMove(tmp))

proc readJson*(dst: var CanonRawJson; p: var JsonParser; unknownFields: UnknownFieldPolicy) =
  var tmp = ""
  writeParsedJson(tmp, p, normalized = true)
  dst = CanonRawJson(ensureMove(tmp))

proc readJson*(dst: var char; p: var JsonParser; unknownFields: UnknownFieldPolicy) =
  if p.tok == tkString and len(p.a) == 1:
    dst = p.a[0]
    discard getTok(p)
  elif p.tok == tkInt:
    let n = p.getInt()
    if n >= ord(low(char)) and n <= ord(high(char)):
      dst = char(n)
      discard getTok(p)
    else:
      raiseParseErr(p, "valid char code")
  else:
    raiseParseErr(p, "string of length 1 or int for a char")

proc readJson*(dst: var bool; p: var JsonParser; unknownFields: UnknownFieldPolicy) =
  case p.tok
  of tkTrue:
    dst = true
    discard getTok(p)
  of tkFalse:
    dst = false
    discard getTok(p)
  else:
    raiseParseErr(p, "true or false")

proc readJson*[T: SomeInteger](dst: var T; p: var JsonParser;
                              unknownFields: UnknownFieldPolicy) =
  if p.tok == tkInt:
    let n = getInt(p)
    if fitsIntType[T](n):
      dst = T(n)
      discard getTok(p)
    else:
      raiseParseErr(p, "int in range for target type")
  else:
    raiseParseErr(p, "int")

proc readJson*[T: SomeFloat](dst: var T; p: var JsonParser;
                            unknownFields: UnknownFieldPolicy) =
  if p.tok == tkFloat:
    dst = T(getFloat(p))
    discard getTok(p)
  elif p.tok == tkInt:
    dst = T(getInt(p))
    discard getTok(p)
  else:
    raiseParseErr(p, "float or int")

proc readJson*[T: enum](dst: var T; p: var JsonParser;
                       unknownFields: UnknownFieldPolicy) =
  if p.tok == tkString:
    try:
      dst = parseEnum[T](p.a)
      discard getTok(p)
    except ValueError:
      raiseParseErr(p, "valid enum name")
  elif p.tok == tkInt:
    if parseEnumValue(getInt(p), dst):
      discard getTok(p)
    else:
      raiseParseErr(p, "valid enum value")
  else:
    raiseParseErr(p, "string or int for a enum")

proc readJson*[T](dst: var seq[T]; p: var JsonParser;
                  unknownFields: UnknownFieldPolicy) =
  eat(p, tkBracketLe)
  while p.tok != tkBracketRi:
    var tmp: T
    readJson(tmp, p, unknownFields)
    dst.add(tmp)
    expectArraySeparator(p)
  eat(p, tkBracketRi)

proc readJson*[S, T](dst: var array[S, T]; p: var JsonParser;
                     unknownFields: UnknownFieldPolicy) =
  eat(p, tkBracketLe)
  var i = int(low(dst))
  let hi = int(high(dst))
  while i <= hi:
    if p.tok == tkBracketRi:
      raiseParseErr(p, "array element")
    readJson(dst[S(i)], p, unknownFields)
    inc(i)
    if i <= hi:
      expectArraySeparator(p)
  eat(p, tkBracketRi)

proc readJson*[T](dst: var (SomeSet[T]|set[T]); p: var JsonParser;
                  unknownFields: UnknownFieldPolicy) =
  eat(p, tkBracketLe)
  while p.tok != tkBracketRi:
    var tmp: T
    readJson(tmp, p, unknownFields)
    dst.incl(tmp)
    expectArraySeparator(p)
  eat(p, tkBracketRi)

proc readJson*[T](dst: var (Table[string, T]|OrderedTable[string, T]); p: var JsonParser;
                  unknownFields: UnknownFieldPolicy) =
  eat(p, tkCurlyLe)
  while p.tok != tkCurlyRi:
    if p.tok != tkString:
      raiseParseErr(p, "string literal as key")
    var key = p.a
    discard getTok(p)
    eat(p, tkColon)
    readJson(mgetOrPut(dst, key, default(T)), p, unknownFields)
    expectObjectSeparator(p)
  eat(p, tkCurlyRi)

proc readJson*[T](dst: var ref T; p: var JsonParser;
                  unknownFields: UnknownFieldPolicy) =
  if p.tok == tkNull:
    dst = nil
    discard getTok(p)
  else:
    new(dst)
    readJson(dst[], p, unknownFields)

proc readJson*[T](dst: var Option[T]; p: var JsonParser;
                  unknownFields: UnknownFieldPolicy) =
  if p.tok != tkNull:
    var tmp: T
    readJson(tmp, p, unknownFields)
    dst = some(tmp)
  else:
    dst = none[T]()
    discard getTok(p)

proc skipJson*(p: var JsonParser) =
  case p.tok
  of tkString, tkInt, tkFloat, tkTrue, tkFalse, tkNull, tkNumberError:
    discard getTok(p)
  of tkCurlyLe:
    discard getTok(p)
    while p.tok != tkCurlyRi:
      if p.tok != tkString:
        raiseParseErr(p, "string literal as key")
      discard getTok(p)
      eat(p, tkColon)
      skipJson(p)
      expectObjectSeparator(p)
    eat(p, tkCurlyRi)
  of tkBracketLe:
    discard getTok(p)
    while p.tok != tkBracketRi:
      skipJson(p)
      expectArraySeparator(p)
    eat(p, tkBracketRi)
  of tkError, tkCurlyRi, tkBracketRi, tkColon, tkComma, tkEof:
    raiseParseErr(p, "JSON value")

template readFieldsInner(parser, body) =
  expectObjectSeparator(parser)
  while parser.tok != tkCurlyRi:
    if parser.tok != tkString:
      raiseParseErr(parser, "string literal as key")
    body
    expectObjectSeparator(parser)

template raiseWrongKey(parser, unknownFields) =
  if unknownFields == ufSkip:
    discard getTok(parser)
    eat(parser, tkColon)
    skipJson(parser)
  else:
    raiseParseErr(parser, "valid object field")

template getFieldValue(parser, tmpSym, fieldSym, unknownFields) =
  discard getTok(parser)
  eat(parser, tkColon)
  readJson(tmpSym.fieldSym, parser, unknownFields)

template getKindValue(parser, tmpSym, kindSym, kindType, unknownFields) =
  discard getTok(parser)
  eat(parser, tkColon)
  var kindTmp: kindType
  readJson(kindTmp, parser, unknownFields)
  tmpSym = (typeof tmpSym)(kindSym: kindTmp)

template jsonxFieldCaseKey(parser): untyped =
  when defined(jsonxNormalized):
    newCall(bindSym"nimIdentNormalize", newDotExpr(parser, ident"a"))
  else:
    newDotExpr(parser, ident"a")

template jsonxFieldLiteral(name: string): untyped =
  when defined(jsonxNormalized):
    newLit(nimIdentNormalize(name))
  else:
    newLit(name)

template caseANormalized: untyped =
  nnkCaseStmt.newTree(jsonxFieldCaseKey(parser))

proc foldObjectBody(typeNode, tmpSym, parser, unknownFields: NimNode): NimNode =
  case typeNode.kind
  of nnkEmpty:
    result = newNimNode(nnkNone)
  of nnkRecList, nnkTupleTy:
    result = caseANormalized()
    for it in typeNode:
      let x = foldObjectBody(it, tmpSym, parser, unknownFields)
      if x.kind != nnkNone: result.add x
    result.add nnkElse.newTree(getAst(raiseWrongKey(parser, unknownFields)))
  of nnkIdentDefs:
    expectLen(typeNode, 3)
    let fieldSym = typeNode[0]
    result = nnkOfBranch.newTree(jsonxFieldLiteral(fieldSym.strVal),
        getAst(getFieldValue(parser, tmpSym, fieldSym, unknownFields)))
  of nnkRecCase:
    let kindSym = typeNode[0][0]
    let kindType = typeNode[0][1]
    result = nnkOfBranch.newTree(jsonxFieldLiteral(kindSym.strVal),
        getAst(getKindValue(parser, tmpSym, kindSym, kindType, unknownFields)))
    let inner = nnkCaseStmt.newTree(nnkDotExpr.newTree(tmpSym, kindSym))
    for i in 1..<typeNode.len:
      let x = foldObjectBody(typeNode[i], tmpSym, parser, unknownFields)
      if x.kind != nnkNone: inner.add x
    result[^1].add getAst(readFieldsInner(parser, inner))
  of nnkOfBranch, nnkElse:
    result = copyNimNode(typeNode)
    for i in 0..typeNode.len-2:
      result.add copyNimTree(typeNode[i])
    let inner = newNimNode(nnkStmtListExpr)
    if typeNode[^1].kind == nnkIdentDefs:
      inner.add caseANormalized()
    let x = foldObjectBody(typeNode[^1], tmpSym, parser, unknownFields)
    if x.kind == nnkCaseStmt: inner.add x
    elif x.kind != nnkNone: inner[^1].add x
    if typeNode[^1].kind == nnkIdentDefs:
      inner[^1].add nnkElse.newTree(getAst(raiseWrongKey(parser, unknownFields)))
    result.add inner
  of nnkObjectTy:
    expectKind(typeNode[0], nnkEmpty)
    expectKind(typeNode[1], {nnkEmpty, nnkOfInherit})
    result = newNimNode(nnkNone)
    if typeNode[1].kind == nnkOfInherit:
      let base = typeNode[1][0]
      var impl = getTypeImpl(base)
      while impl.kind in {nnkRefTy, nnkPtrTy}:
        impl = getTypeImpl(impl[0])
      result = foldObjectBody(impl, tmpSym, parser, unknownFields)
    let body = typeNode[2]
    let x = foldObjectBody(body, tmpSym, parser, unknownFields)
    if result.kind != nnkNone:
      if x.kind != nnkNone: # merge case statements
        expectKind(result, nnkCaseStmt)
        for i in 1..x.len-2: result.insert(result.len-1, x[i])
    else: result = x
  else:
    error("unhandled kind: " & $typeNode.kind, typeNode)

macro assignObjectImpl(dst: typed; parser: JsonParser;
                       unknownFields: UnknownFieldPolicy): untyped =
  let typeSym = getTypeInst(dst)
  let typeNode = if typeSym.kind in {nnkTupleTy, nnkTupleConstr}:
    typeSym
  else:
    typeSym.getTypeImpl
  result = newStmtList()
  let body = foldObjectBody(typeNode, dst, parser, unknownFields)
  if body.kind != nnkNone:
    result.add body

proc readJson*[T: object](dst: var T; p: var JsonParser;
                          unknownFields: UnknownFieldPolicy) =
  eat(p, tkCurlyLe)
  while p.tok != tkCurlyRi:
    if p.tok != tkString:
      raiseParseErr(p, "string literal as key")
    assignObjectImpl(dst, p, unknownFields)
    expectObjectSeparator(p)
  eat(p, tkCurlyRi)

proc readJson*[T: tuple](dst: var T; p: var JsonParser;
                         unknownFields: UnknownFieldPolicy) =
  when isNamedTuple(T):
    eat(p, tkCurlyLe)
    while p.tok != tkCurlyRi:
      if p.tok != tkString:
        raiseParseErr(p, "string literal as key")
      assignObjectImpl(dst, p, unknownFields)
      expectObjectSeparator(p)
    eat(p, tkCurlyRi)
  else:
    eat(p, tkBracketLe)
    for v in dst.fields:
      if p.tok == tkBracketRi:
        raiseParseErr(p, "tuple element")
      readJson(v, p, unknownFields)
      expectArraySeparator(p)
    eat(p, tkBracketRi)

proc fromJson*[T](s: Stream, t: typedesc[T];
                  unknownFields = ufSkip): T =
  ## Unmarshals the specified stream into the type specified.
  ##
  ## Known limitations:
  ##
  ##   * Heterogeneous arrays are not supported.
  ##   * Sets in object variants are not supported.
  ##   * Not nil annotations are not supported.
  ##
  if s.isNil:
    raise newException(IOError, "input stream is nil")
  var p: JsonParser
  open(p, s, "unknown file")
  try:
    discard getTok(p)
    readJson(result, p, unknownFields)
    eat(p, tkEof)
  finally:
    close(p)

proc fromJson*[T](s: Stream, dst: var T;
                  unknownFields = ufSkip) =
  ## Unmarshals the specified stream into the location specified.
  if s.isNil:
    raise newException(IOError, "input stream is nil")
  var p: JsonParser
  open(p, s, "unknown file")
  try:
    discard getTok(p)
    readJson(dst, p, unknownFields)
    eat(p, tkEof)
  finally:
    close(p)

proc fromString[T](input: string; dst: var T;
                   unknownFields: UnknownFieldPolicy) {.inline.} =
  var p: JsonParser
  open(p, input, "unknown file")
  try:
    discard getTok(p)
    readJson(dst, p, unknownFields)
    eat(p, tkEof)
  finally:
    close(p)

proc fromJson*[T](input: string, t: typedesc[T];
                  unknownFields = ufSkip): T =
  ## Unmarshals the specified string into the type specified.
  fromString(input, result, unknownFields)

proc fromJson*[T](input: RawJson, t: typedesc[T];
                  unknownFields = ufSkip): T {.inline.} =
  fromJson(string(input), t, unknownFields)

proc fromJson*[T](input: string, dst: var T;
                  unknownFields = ufSkip) =
  ## Unmarshals the specified string into the location specified.
  fromString(input, dst, unknownFields)

proc fromJson*[T](input: RawJson, dst: var T;
                  unknownFields = ufSkip) {.inline.} =
  fromJson(string(input), dst, unknownFields)

proc fromFile*[T](path: Path, dst: var T;
                  unknownFields = ufSkip) =
  ## Unmarshals the specified JSON file into the location specified.
  let s = streams.open(path, fmRead)
  if s.isNil:
    raise newException(IOError, "cannot open file: " & path.string)
  fromJson(s, dst, unknownFields)

proc fromFile*[T](path: Path, t: typedesc[T];
                  unknownFields = ufSkip): T =
  ## Unmarshals the specified JSON file into the type specified.
  fromFile(path, result, unknownFields)

proc toJson*[T](x: T): string =
  ## Serializes the specified value to a JSON string.
  let s = streams.open("")
  s.writeJson(x)
  result = move(s.s)

template whileJsonItems(s, x, xType, unknownFields, body: untyped) =
  var p: JsonParser
  open(p, s, "unknown file")
  try:
    discard getTok(p)
    eat(p, tkBracketLe)
    while p.tok != tkBracketRi:
      var x: xType
      readJson(x, p, unknownFields)
      body
      expectArraySeparator(p)
    eat(p, tkBracketRi)
    eat(p, tkEof)
  finally:
    close(p)

macro jsonItems*(x: ForLoopStmt): untyped =
  ## Unmarshals a JArray into the type specified, one items at a time.
  expectLen(x, 3)
  let iterVar = x[0]
  expectKind(x[1], nnkCall)
  if x[1].len notin {3, 4}:
    error("jsonItems expects a stream, item type, and optional UnknownFieldPolicy", x[1])
  let
    iterType = x[1][2]
    strmVar = x[1][1]
    unknownFields = if x[1].len == 4: x[1][3] else: bindSym"ufSkip"
    body = x[^1]
  result = newBlockStmt(getAst(
    whileJsonItems(strmVar, iterVar, iterType, unknownFields, body)))
