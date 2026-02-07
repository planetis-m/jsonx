import jsonx

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

when isMainModule:
  let a = fromJson("""{"Apple":{"apple":"world"}}""", Bar)
  doAssert a.kind == Apple
  doAssert a.apple == "world"
