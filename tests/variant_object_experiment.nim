import jsonx
import jsonx/parsejson
import std/strutils

type
  Fruit = enum
    Apple, Banana, Orange
  Bar = object
    case kind: Fruit
    of Banana:
      bad: float
      banana: int
    of Apple:
      apple: string
    else:
      discard

proc readJson(dst: var Bar; p: var JsonParser) =
  eat(p, tkCurlyLe)
  while p.tok != tkCurlyRi:
    if p.tok != tkString:
      raiseParseErr(p, "string literal as key")

    var kindTmp: Fruit
    case nimIdentNormalize(p.a)
    of "Banana":
      kindTmp = Banana
    of "Apple":
      kindTmp = Apple
    of "Orange":
      kindTmp = Orange
    else:
      raiseParseErr(p, "valid object field")

    dst = (typeof dst)(kind: kindTmp)
    discard getTok(p)
    eat(p, tkColon)

    eat(p, tkCurlyLe)
    while p.tok != tkCurlyRi:
      if p.tok != tkString:
        raiseParseErr(p, "string literal as key")
      case dst.kind
      of Banana:
        case nimIdentNormalize(p.a)
        of "bad":
          discard getTok(p)
          eat(p, tkColon)
          readJson(dst.bad, p)
        of "banana":
          discard getTok(p)
          eat(p, tkColon)
          readJson(dst.banana, p)
        else:
          raiseParseErr(p, "valid object field")
      of Apple:
        case nimIdentNormalize(p.a)
        of "apple":
          discard getTok(p)
          eat(p, tkColon)
          readJson(dst.apple, p)
        else:
          raiseParseErr(p, "valid object field")
      else:
        case nimIdentNormalize(p.a)
        else:
          raiseParseErr(p, "valid object field")
      expectObjectSeparator(p)
    eat(p, tkCurlyRi)

    expectObjectSeparator(p)
  eat(p, tkCurlyRi)

when isMainModule:
  let a = fromJson("""{"Apple":{"apple":"world"}}""", Bar)
  doAssert a.kind == Apple
  doAssert a.apple == "world"
