import std/[macros, strutils, options, tables, sets]
import jsonx/[parsejson, streams]
from std/typetraits import isNamedTuple, distinctBase

# serialization
proc escapeJsonUnquoted*(x: string; s: Stream) =
  ## Converts a string `s` to its JSON representation without quotes.
  ## Appends to ``result``.
  for c in x:
    case c
    of '\L': streams.write(s, "\\n")
    of '\b': streams.write(s, "\\b")
    of '\f': streams.write(s, "\\f")
    of '\t': streams.write(s, "\\t")
    of '\v': streams.write(s, "\\u000b")
    of '\r': streams.write(s, "\\r")
    of '"': streams.write(s, "\\\"")
    of '\0'..'\7': streams.write(s, "\\u000" & $ord(c))
    of '\14'..'\31': streams.write(s, "\\u00" & toHex(ord(c), 2))
    of '\\': streams.write(s, "\\\\")
    else: streams.write(s, c)

proc escapeJson*(s: Stream; x: string) =
  ## Converts a string `s` to its JSON representation with quotes.
  ## Appends to ``result``.
  streams.write(s, "\"")
  escapeJsonUnquoted(x, s)
  streams.write(s, "\"")

proc writeJsonNull*(s: Stream) =
  ## Creates a new JNull.
  streams.write(s, "null")

proc writeJson*(s: Stream; x: string) =
  ## Creates a new JString.
  escapeJson(s, x)

proc writeJson*(s: Stream; b: bool) =
  ## Creates a new JBool.
  streams.write(s, if b: "true" else: "false")

proc writeJson*(s: Stream; n: BiggestInt) =
  ## Creates a new JInt.
  streams.write(s, $n)

proc writeJson*(s: Stream; n: float) =
  ## Creates a new JFloat.
  streams.write(s, $n)

proc writeJson*(s: Stream; o: enum) =
  ## Construct a Json that represents the specified enum value as a
  ## string. Creates a new JString.
  writeJson(s, $o)

proc writeJson*[T](s: Stream; elements: openArray[T]) =
  ## Generic constructor for JSON data. Creates a new JArray.
  var comma = false
  streams.write(s, "[")
  for elem in elements:
    if comma: streams.write(s, ",")
    else: comma = true
    writeJson(s, elem)
  streams.write(s, "]")

proc writeJson*[T](s: Stream; o: SomeSet[T]|set[T]) =
  var comma = false
  streams.write(s, "[")
  for elem in o.items:
    if comma: streams.write(s, ",")
    else: comma = true
    writeJson(s, elem)
  streams.write(s, "]")

proc writeJson*[T](s: Stream; o: (Table[string, T]|OrderedTable[string, T])) =
  var comma = false
  streams.write(s, "{")
  for k, v in o.pairs:
    if comma: streams.write(s, ",")
    else: comma = true
    escapeJson(s, k)
    streams.write(s, ":")
    writeJson(s, v)
  streams.write(s, "}")

proc writeJson*(s: Stream; o: ref object) =
  ## Generic constructor for JSON data. Creates a new JObject
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
  ## Generic constructor for JSON data. Creates a new JObject
  var comma = false
  when isNamedTuple(T):
    streams.write(s, "{")
    for k, v in o.fieldPairs:
      if comma: streams.write(s, ",")
      else: comma = true
      escapeJson(s, k)
      streams.write(s, ":")
      writeJson(s, v)
    streams.write(s, "}")
  else:
    {.error: "Tuples with unnamed fields not supported".}

proc writeJson*[T: object](s: Stream; o: T) =
  ## Generic constructor for JSON data. Creates a new JObject
  var comma = false
  streams.write(s, "{")
  for k, v in o.fieldPairs:
    if comma: streams.write(s, ",")
    else: comma = true
    escapeJson(s, k)
    streams.write(s, ":")
    writeJson(s, v)
  streams.write(s, "}")

# deserialization
proc readJson*(dst: var string; p: var JsonParser) =
  if p.tok == tkNull:
    dst = ""
    discard getTok(p)
  elif p.tok == tkString:
    dst = p.a
    discard getTok(p)
  else:
    raiseParseErr(p, "string or null")

proc readJson*(dst: var char; p: var JsonParser) =
  if p.tok == tkString and len(p.a) == 1:
    dst = p.a[0]
    discard getTok(p)
  elif p.tok == tkInt:
    dst = char(parseInt(p.a))
    discard getTok(p)
  else:
    raiseParseErr(p, "string of length 1 or int for a char")

proc readJson*(dst: var bool; p: var JsonParser) =
  case p.tok
  of tkTrue:
    dst = true
    discard getTok(p)
  of tkFalse:
    dst = false
    discard getTok(p)
  else:
    raiseParseErr(p, "'true' or 'false' for a bool")

proc readJson*[T: SomeInteger](dst: var T; p: var JsonParser) =
  if p.tok == tkInt:
    dst = T(parseInt(p.a))
    discard getTok(p)
  else:
    raiseParseErr(p, "int")

proc readJson*[T: SomeFloat](dst: var T; p: var JsonParser) =
  if p.tok == tkFloat:
    dst = T(parseFloat(p.a))
    discard getTok(p)
  elif p.tok == tkInt:
    dst = T(parseInt(p.a))
    discard getTok(p)
  else:
    raiseParseErr(p, "float or int")

proc readJson*[T: enum](dst: var T; p: var JsonParser) =
  if p.tok == tkString:
    dst = parseEnum[T](p.a)
    discard getTok(p)
  elif p.tok == tkInt:
    dst = T(parseInt(p.a))
    discard getTok(p)
  else:
    raiseParseErr(p, "string or int for a enum")

proc readJson*[T](dst: var seq[T]; p: var JsonParser) =
  eat(p, tkBracketLe)
  dst.setLen(0)
  while p.tok != tkBracketRi:
    var tmp: T
    readJson(tmp, p)
    dst.add(tmp)
    if p.tok != tkComma: break
    discard getTok(p)
  eat(p, tkBracketRi)

proc readJson*[S, T](dst: var array[S, T]; p: var JsonParser) =
  eat(p, tkBracketLe)
  var i = int(low(dst))
  while p.tok != tkBracketRi:
    readJson(dst[S(i)], p)
    inc(i)
    if p.tok != tkComma: break
    discard getTok(p)
  #if i <= high(dst):
    #raise newException(RangeDefect, "array not filled")
  eat(p, tkBracketRi)

proc readJson*[T](dst: var (SomeSet[T]|set[T]); p: var JsonParser) =
  eat(p, tkBracketLe)
  while p.tok != tkBracketRi:
    var tmp: T
    readJson(tmp, p)
    dst.incl(tmp)
    if p.tok != tkComma: break
    discard getTok(p)
  eat(p, tkBracketRi)

proc readJson*[T](dst: var (Table[string, T]|OrderedTable[string, T]); p: var JsonParser) =
  eat(p, tkCurlyLe)
  while p.tok != tkCurlyRi:
    if p.tok != tkString:
      raiseParseErr(p, "string literal as key")
    var key = p.a
    discard getTok(p)
    eat(p, tkColon)
    readJson(mgetOrPut(dst, key, default(T)), p)
    if p.tok != tkComma: break
    discard getTok(p)
  eat(p, tkCurlyRi)

proc readJson*[T](dst: var ref T; p: var JsonParser) =
  if p.tok == tkNull:
    dst = nil
    discard getTok(p)
  elif p.tok == tkCurlyLe:
    new(dst)
    readJson(dst[], p)
  else:
    raiseParseErr(p, "object or null")

proc readJson*[T](dst: var Option[T]; p: var JsonParser) =
  if p.tok != tkNull:
    var tmp: T
    readJson(tmp, p)
    dst = some(tmp)
  else:
    dst = none[T]()
    discard getTok(p)

proc detectIncompatibleType(typeExpr: NimNode) =
  if typeExpr.kind == nnkTupleConstr:
    error("Use a named tuple instead of: " & typeExpr.repr)

proc skipJson(p: var JsonParser) =
  case p.tok
  of tkString, tkInt, tkFloat, tkTrue, tkFalse, tkNull:
    discard getTok(p)
  of tkCurlyLe:
    discard getTok(p)
    while p.tok != tkCurlyRi:
      if p.tok != tkString:
        raiseParseErr(p, "string literal as key")
      discard getTok(p)
      eat(p, tkColon)
      skipJson(p)
      if p.tok != tkComma: break
      discard getTok(p)
    eat(p, tkCurlyRi)
  of tkBracketLe:
    discard getTok(p)
    while p.tok != tkBracketRi:
      skipJson(p)
      if p.tok != tkComma: break
      discard getTok(p)
    eat(p, tkBracketRi)
  of tkError, tkCurlyRi, tkBracketRi, tkColon, tkComma, tkEof:
    raiseParseErr(p, "{")

template readFieldsInner(parser, body) =
  if p.tok != tkComma: break
  discard getTok(p)
  while parser.tok != tkCurlyRi:
    if parser.tok != tkString:
      raiseParseErr(parser, "string literal as key")
    body
    if parser.tok != tkComma: break
    discard getTok(parser)

template raiseWrongKey(parser) =
  when defined(emiLenient):
    discard getTok(parser)
    eat(parser, tkColon)
    skipJson(parser)
  else: raiseParseErr(parser, "valid object field")

template getFieldValue(parser, tmpSym, fieldSym) =
  discard getTok(parser)
  eat(parser, tkColon)
  readJson(tmpSym.fieldSym, parser)

template getKindValue(parser, tmpSym, kindSym, kindType) =
  discard getTok(parser)
  eat(parser, tkColon)
  var kindTmp: kindType
  readJson(kindTmp, parser)
  tmpSym = (typeof tmpSym)(kindSym: kindTmp)

template caseANormalized: untyped =
  nnkCaseStmt.newTree(newCall(bindSym"nimIdentNormalize", newDotExpr(parser, ident"a")))

proc foldObjectBody(typeNode, tmpSym, parser: NimNode): NimNode =
  case typeNode.kind
  of nnkEmpty:
    result = newNimNode(nnkNone)
  of nnkRecList, nnkTupleTy:
    result = caseANormalized()
    for it in typeNode:
      let x = foldObjectBody(it, tmpSym, parser)
      if x.kind != nnkNone: result.add x
    result.add nnkElse.newTree(getAst(raiseWrongKey(parser)))
  of nnkIdentDefs:
    expectLen(typeNode, 3)
    let fieldSym = typeNode[0]
    let fieldType = typeNode[1]
    detectIncompatibleType(fieldType)
    result = nnkOfBranch.newTree(newLit(nimIdentNormalize(fieldSym.strVal)),
        getAst(getFieldValue(parser, tmpSym, fieldSym)))
  of nnkRecCase:
    let kindSym = typeNode[0][0]
    let kindType = typeNode[0][1]
    result = nnkOfBranch.newTree(newLit(nimIdentNormalize(kindSym.strVal)),
        getAst(getKindValue(parser, tmpSym, kindSym, kindType)))
    let inner = nnkCaseStmt.newTree(nnkDotExpr.newTree(tmpSym, kindSym))
    for i in 1..<typeNode.len:
      let x = foldObjectBody(typeNode[i], tmpSym, parser)
      if x.kind != nnkNone: inner.add x
    result[^1].add getAst(readFieldsInner(parser, inner))
  of nnkOfBranch, nnkElse:
    result = copyNimNode(typeNode)
    for i in 0..typeNode.len-2:
      result.add copyNimTree(typeNode[i])
    let inner = newNimNode(nnkStmtListExpr)
    if typeNode[^1].kind == nnkIdentDefs:
      inner.add caseANormalized()
    let x = foldObjectBody(typeNode[^1], tmpSym, parser)
    if x.kind == nnkCaseStmt: inner.add x
    elif x.kind != nnkNone: inner[^1].add x
    if typeNode[^1].kind == nnkIdentDefs:
      inner[^1].add nnkElse.newTree(getAst(raiseWrongKey(parser)))
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
      result = foldObjectBody(impl, tmpSym, parser)
    let body = typeNode[2]
    let x = foldObjectBody(body, tmpSym, parser)
    if result.kind != nnkNone:
      if x.kind != nnkNone: # merge case statements
        expectKind(result, nnkCaseStmt)
        for i in 1..x.len-2: result.insert(result.len-1, x[i])
    else: result = x
  else:
    error("unhandled kind: " & $typeNode.kind, typeNode)

macro assignObjectImpl(dst: typed; parser: JsonParser): untyped =
  let typeSym = getTypeInst(dst)
  result = newStmtList()
  let x = if typeSym.kind in {nnkTupleTy, nnkTupleConstr}:
    detectIncompatibleType(typeSym)
    foldObjectBody(typeSym, dst, parser)
  else:
    foldObjectBody(typeSym.getTypeImpl, dst, parser)
  if x.kind != nnkNone: result.add x

proc readJson*[T: object|tuple](dst: var T; p: var JsonParser) =
  eat(p, tkCurlyLe)
  while p.tok != tkCurlyRi:
    if p.tok != tkString:
      raiseParseErr(p, "string literal as key")
    assignObjectImpl(dst, p)
    if p.tok != tkComma: break
    discard getTok(p)
  eat(p, tkCurlyRi)

proc fromJson*[T](s: Stream, t: typedesc[T]): T =
  ## Unmarshals the specified stream into the type specified.
  ##
  ## Known limitations:
  ##
  ##   * Heterogeneous arrays are not supported.
  ##   * Sets in object variants are not supported.
  ##   * Not nil annotations are not supported.
  ##
  var p: JsonParser
  open(p, s, "unknown file")
  try:
    discard getTok(p)
    readJson(result, p)
    eat(p, tkEof)
  finally:
    close(p)

proc fromJson*[T](s: Stream, dst: var T) =
  ## Unmarshals the specified stream into the location specified.
  var p: JsonParser
  open(p, s, "unknown file")
  try:
    discard getTok(p)
    readJson(dst, p)
    eat(p, tkEof)
  finally:
    close(p)

proc fromJson*[T](input: string, t: typedesc[T]): T =
  ## Unmarshals the specified string into the type specified.
  let s = streams.open(input)
  result = fromJson(s, t)

proc fromJson*[T](input: string, dst: var T) =
  ## Unmarshals the specified string into the location specified.
  let s = streams.open(input)
  fromJson(s, dst)

proc toJson*[T](x: T): string =
  ## Serializes the specified value to a JSON string.
  let s = streams.open("")
  s.writeJson(x)
  result = s.s

template whileJsonItems(s, x, xType, body: untyped) =
  var p: JsonParser
  open(p, s, "unknown file")
  try:
    discard getTok(p)
    eat(p, tkBracketLe)
    while p.tok != tkBracketRi:
      var x: xType
      readJson(x, p)
      body
      if p.tok != tkComma: break
      discard getTok(p)
    eat(p, tkBracketRi)
    eat(p, tkEof)
  finally:
    close(p)

macro jsonItems*(x: ForLoopStmt): untyped =
  ## Unmarshals a JArray into the type specified, one items at a time.
  expectLen(x, 3)
  let iterVar = x[0]
  expectLen(x[1], 3)
  let
    iterType = x[1][2]
    strmVar = x[1][1]
    body = x[^1]
  result = newBlockStmt(getAst(whileJsonItems(strmVar, iterVar, iterType, body)))
