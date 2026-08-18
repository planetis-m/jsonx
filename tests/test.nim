import jsonx, std/[enumerate, math, options, paths, sets, tables]
import jsonx/parsejson
import jsonx/streams

type
  Foo = ref object
    value: int
    next: Foo
  Fruit = enum
    Apple, Banana, Orange
  Stuff = enum
    NotApple = 1, NotBanana, NotOrange
  Baz = distinct string
  BarBaz = array[2..8, int]
  FooBaz = object
    val: BarBar
  BarBar = tuple
    value: Baz
  Bar = ref object
    case kind: Fruit
    of Banana:
      bad: float
      banana: int
    of Apple: apple: string
    else: discard
  Rejected = object
    val: (int,)
  ContentNodeKind = enum
    P, Br, Text
  ContentNode = object
    case kind: ContentNodeKind
    of P: pChildren: seq[ContentNode]
    of Br: discard
    of Text: textStr: string
  BazBat = ref object of RootObj
  BarFoo = ref object of BazBat
    t: float
  BazFoo = ref object of BarFoo
  FooBar = ref object of BazFoo
    x: int
    v: string
  Empty = object
  IrisPlant = object
    sepalLength: float32
    sepalWidth: float32
    petalLength: float32
    petalWidth: float32
    species: string
  Gender = enum
    male, female
  Relation = enum
    biological, step
  Responder = object
    name: string
    gender: Gender
    occupation: string
    age: int
    siblings: seq[Sibling]
  Sibling = object
    sex: Gender
    birthYear: int
    relation: Relation
    alive: bool
  ImageUrl = object
    url: string
  ContentItem = object
    `type`: string
    image_url: Option[ImageUrl]
    text: Option[string]
  ChatMessage = object
    role: string
    content: seq[ContentItem]
  ChatRequest = object
    model: string
    max_tokens: int
    messages: seq[ChatMessage]
  ChatMessageOut = object
    role: string
    content: string
  ChatChoice = object
    index: int
    message: ChatMessageOut
  ChatResponse = object
    choices: seq[ChatChoice]
  LenientKnown = object
    known: int
  NestedKnown = object
    child: LenientKnown
  RawJsonHolder = object
    payload: RawJson
  CanonRawJsonHolder = object
    payload: CanonRawJson

proc rawText(x: RawJson): string =
  result = string(x)

proc canonicalText(x: CanonRawJson): string =
  result = string(x)

proc readJson(dst: var Baz; p: var JsonParser;
              unknownFields: UnknownFieldPolicy) =
  var tmp: string
  readJson(tmp, p, unknownFields)
  dst = Baz(tmp)
proc `==`(a, b: Baz): bool {.borrow.}

proc toJsonString[T](x: T): string =
  let s = streams.open("")
  s.writeJson(x)
  result = s.s

proc jsonToFromString[T](x: T): T =
  let s = streams.open(toJsonString(x))
  result = s.fromJson(typeof x)

block:
  let data = [1, 2, 3]
  let s = toJson(data)
  let a = fromJson(s, typeof data)
  assert a == data
block:
  let data = FooBar(v: "hello", t: 1.0)
  let s = toJson(data)
  var dst: FooBar
  fromJson(s, dst)
  assert dst.v == data.v
  assert dst.t == data.t
block:
  let data = (ref IrisPlant)(
    sepalLength: 5.1,
    sepalWidth: 3.5,
    petalLength: 1.4,
    petalWidth: 0.2,
    species: "setosa"
  )
  let s = toJson(data)
  var dst: ref IrisPlant
  fromJson(s, dst)
  assert dst[] == data[]
block:
  let data: ref seq[int] = new seq[int]
  data[] = @[1, 2, 3]
  doAssert toJson(data) == "[1,2,3]"
block:
  let data: ref string = new string
  data[] = "hello"
  doAssert toJson(data) == "\"hello\""
block:
  let data: ref int = new int
  data[] = 42
  doAssert toJson(data) == "42"
block:
  var data: ref seq[int]
  doAssert toJson(data) == "null"
block:
  var dst: ref seq[int]
  fromJson("[1,2,3]", dst)
  doAssert not dst.isNil
  doAssert dst[] == @[1, 2, 3]
block:
  var dst: ref string
  fromJson(""""hello"""", dst)
  doAssert not dst.isNil
  doAssert dst[] == "hello"
block:
  var dst: ref int
  fromJson("42", dst)
  doAssert not dst.isNil
  doAssert dst[] == 42
block:
  var dst: ref seq[int]
  fromJson("null", dst)
  doAssert dst.isNil
block:
  var dst: ref string
  fromJson("null", dst)
  doAssert dst.isNil
block:
  let s = """{"value": 7, "next": null}"""
  var dst: Option[Foo]
  fromJson(s, dst)
  assert dst.isSome
  assert dst.get.value == 7
  assert dst.get.next.isNil
block:
  let b64 = "use some random values"
  let request = ChatRequest(
    model: "allenai/olmOCR-2-7B-1025",
    max_tokens: 4092,
    messages: @[
      ChatMessage(
        role: "user",
        content: @[
          ContentItem(
            `type`: "text",
            image_url: none(ImageUrl),
            text: some("Extract the text exactly.")
          ),
          ContentItem(
            `type`: "image_url",
            image_url: some(ImageUrl(url: "data:image/jpeg;base64," & b64)),
            text: none(string)
          )
        ]
      )
    ]
  )
  let reqJson = toJsonString(request)
  let reqBack = fromJson(reqJson, ChatRequest)
  let reqJsonBack = toJsonString(reqBack)

  let respJson = """{"choices":[{"index":0,"message":{"role":"assistant","content":"ok"}}]}"""
  let resp = fromJson(respJson, ChatResponse)
  let respJsonNorm = toJsonString(resp)
  let respBack = fromJson(respJsonNorm, ChatResponse)
  let respJsonBack = toJsonString(respBack)

  doAssert reqJson.len > 0
  doAssert reqJsonBack == reqJson
  doAssert respJsonBack == respJsonNorm
block:
  let data = [0, 1, 2, 3, 4, 5, 6]
  let a = jsonToFromString(data)
  assert a == data
block:
  let data: array[Fruit, int] = [0, 1, 2]
  let a = jsonToFromString(data)
  assert a == data
block:
  doAssertRaises(JsonParsingError):
    var a: array[0..1, int]
    fromJson("[1]", a)
block:
  doAssertRaises(JsonParsingError):
    var a: array[0..1, int]
    fromJson("[1,2,3]", a)
block:
  doAssertRaises(IOError):
    var x: int
    fromFile(Path"/tmp/jsonx-missing-file-test-should-not-exist", x)
block:
  let data = "hello world"
  let a = jsonToFromString(data)
  assert a == data
block:
  doAssertRaises(ValueError):
    discard toJson(NaN)
block:
  doAssertRaises(ValueError):
    discard toJson(Inf)
block:
  doAssertRaises(ValueError):
    discard toJson(NegInf)
block:
  doAssertRaises(JsonParsingError):
    discard fromJson("256", uint8)
block:
  doAssertRaises(JsonParsingError):
    discard fromJson("-1", uint8)
block:
  doAssertRaises(JsonParsingError):
    discard fromJson("256", char)
block:
  doAssertRaises(JsonParsingError):
    discard fromJson("3", Fruit)
block:
  doAssertRaises(JsonParsingError):
    discard fromJson(""""C"""", Fruit)
block:
  let raw = fromJson(""" { "answer" : [1, {"x" : "\u0041"}], "ok" : true } """, RawJson)
  doAssert rawText(raw) == """{"answer":[1,{"x":"A"}],"ok":true}"""
  doAssert toJson(raw) == rawText(raw)
block:
  let raw = fromJson("""{"z":0,"a":1,"m":2}""", RawJson)
  doAssert rawText(raw) == """{"z":0,"a":1,"m":2}"""
block:
  let raw = fromJson("""{"b":1,"a":2,"b":3,"a":4}""", RawJson)
  doAssert rawText(raw) == """{"b":1,"a":2,"b":3,"a":4}"""
block:
  let raw = fromJson("""{"z":0,"a":1,"m":2}""", CanonRawJson)
  doAssert canonicalText(raw) == """{"a":1,"m":2,"z":0}"""
block:
  let raw = fromJson("""{"b":1,"a":2,"b":3,"a":4}""", CanonRawJson)
  doAssert canonicalText(raw) == """{"a":4,"b":3}"""
block:
  let raw = fromJson(""" "\u0041\n" """, RawJson)
  doAssert rawText(raw) == "\"A\\n\""
  doAssert fromJson(toJson(raw), string) == "A\n"
block:
  let data = RawJsonHolder(
    payload: RawJson("""{"x":1,"items":[true,null,"ok"]}""")
  )
  let s = toJsonString(data)
  doAssert s == """{"payload":{"x":1,"items":[true,null,"ok"]}}"""
  let parsed = fromJson("""{"payload": { "x" : 1, "items" : [true, null, "ok"] }}""", RawJsonHolder)
  doAssert rawText(parsed.payload) == """{"x":1,"items":[true,null,"ok"]}"""
block:
  let data = CanonRawJsonHolder(
    payload: CanonRawJson("""{"x":1,"items":[true,null,"ok"]}""")
  )
  let s = toJsonString(data)
  doAssert s == """{"payload":{"x":1,"items":[true,null,"ok"]}}"""
  let parsed = fromJson("""{"payload": { "x" : 1, "items" : [true, null, "ok"] }}""",
    CanonRawJsonHolder)
  doAssert canonicalText(parsed.payload) == """{"items":[true,null,"ok"],"x":1}"""
block:
  let s = streams.open("""{"k": [1, 2, true]}""")
  var p: JsonParser
  open(p, s, "inline")
  defer:
    close(p)
  discard getTok(p)
  var raw: RawJson
  readJson(raw, p, ufSkip)
  doAssert rawText(raw) == """{"k":[1,2,true]}"""
block:
  let s = streams.open("""{"k": [1, 2, true]}""")
  var p: JsonParser
  open(p, s, "inline")
  defer:
    close(p)
  discard getTok(p)
  var raw = "prefix:"
  appendRawJson(raw, p)
  doAssert raw == """prefix:{"k":[1,2,true]}"""
block:
  doAssertRaises(JsonParsingError):
    discard fromJson("""{"x":[1,}""", RawJson)
block:
  let invalid = RawJson("""{"unterminated":]""")
  doAssert toJson(invalid) == """{"unterminated":]"""
block:
  let data = @["αβγ", "δεζη", "θικλμ"]
  let a = jsonToFromString(data)
  assert a == data
block:
  let data = @[(x: "3"), (x: "4"), (x: "5")]
  let a = jsonToFromString(data)
  assert a == data
block:
  let data = (1, "x", true)
  let s = toJson(data)
  assert s == """[1,"x",true]"""
  let a = fromJson(s, typeof data)
  assert a == data
block:
  let data = ()
  let s = toJson(data)
  assert s == "[]"
  let a = fromJson(s, typeof data)
  assert a == data
block:
  let data = FooBar(v: "hello", t: 1.0)
  let a = jsonToFromString(data)
  assert a.v == "hello"
  assert a.t == 1.0
block:
  let s = streams.open("{}")
  let a = s.fromJson(Empty)
block:
  let s = streams.open("""{"x": 42}""")
  let a = s.fromJson(tuple[x:int])
  assert(a[0] == 42)
block:
  let data = NotApple
  let a = jsonToFromString(data)
  assert a == data
block:
  var data: set[Fruit]
  data.incl Apple
  data.incl Orange
  let a = jsonToFromString(data)
  assert(a == data)
block:
  let data = Rejected(val: (1,))
  let s = toJsonString(data)
  assert s == """{"val":[1]}"""
  let a = fromJson(s, Rejected)
  assert a == data
block:
  doAssertRaises(JsonParsingError):
    var x: (int, string)
    fromJson("[1]", x)
block:
  doAssertRaises(JsonParsingError):
    var x: (int, string)
    fromJson("""[1,"x",true]""", x)
block:
  doAssertRaises(JsonParsingError):
    var x: tuple[]
    fromJson("[1]", x)
block:
  when defined(jsonxNormalized):
    let s = streams.open("""{"va_l": {"vaLue": "stuff"}}""")
  else:
    let s = streams.open("""{"val": {"value": "stuff"}}""")
  let a = s.fromJson(FooBaz)
  assert(a.val[0] == Baz"stuff")
block:
  let data = some(Foo(value: 5, next: nil))
  let a = jsonToFromString(data)
  assert a.get.value == 5
block:
  let data = some(Empty())
  let a = jsonToFromString(data)
block:
  let data = toHashSet([5'f32, 3, 2])
  let a = jsonToFromString(data)
  assert a == data
block:
  let data = {"a": 5'i32, "b": 9'i32}.toTable
  let a = jsonToFromString(data)
  assert a == data
block:
  let data = Foo(value: 1, next: Foo(value: 2, next: nil))
  let a = jsonToFromString(data)
  assert a.value == 1
  let b = a.next
  assert b.value == 2
block:
  let data = Bar(kind: Apple, apple: "world")
  let a = jsonToFromString(data)
  assert a.kind == Apple
  assert a.apple == "world"
block:
  let data = ContentNode(kind: P, pChildren: @[
    ContentNode(kind: Text, textStr: "mychild"),
    ContentNode(kind: Br)
  ])
  let a = jsonToFromString(data)
  assert $a == $data
block:
  let data = @[
    IrisPlant(sepalLength: 5.1, sepalWidth: 3.5, petalLength: 1.4,
              petalWidth: 0.2, species: "setosa"),
    IrisPlant(sepalLength: 4.9, sepalWidth: 3.0, petalLength: 1.4,
              petalWidth: 0.2, species: "setosa")]
  let s = streams.open(toJsonString(data))
  for (i, x) in enumerate(jsonItems(s, IrisPlant)):
    if i == 0:
      assert x.species == "setosa"
      assert almostEqual(x.sepalWidth, 3.5'f32)
    else:
      assert almostEqual(x.sepalWidth, 3'f32)
block:
  let data = [
    Responder(name: "John Smith", gender: male, occupation: "student", age: 18,
      siblings: @[Sibling(sex: female, birthYear: 1991, relation: biological, alive: true),
                  Sibling(sex: male, birthYear: 1989, relation: step, alive: true)])]
  block:
    var a: seq[Responder]
    let s = streams.open(toJsonString(data))
    for x in jsonItems(s, Responder):
      a.add x
    assert a.len == 1
    assert a[0].gender == male
    assert a[0].siblings.len == 2
  block:
    let s = streams.open(toJsonString(data))
    var a = @data
    a[0].name = "Janne Smith"
    a[0].gender = female
    a[0].siblings[0].birthYear = 1997
    a[0].siblings.add Sibling()
    s.fromJson(a)
    assert a.len == 2
    assert a[0].name == "Janne Smith"
    assert a[0].gender == female
    assert a[0].siblings.len == 3
    assert a[0].siblings[0].birthYear == 1997
    assert a[1].name == "John Smith"
    assert a[1].gender == male
    assert a[1].siblings.len == 2
    assert a[1].siblings[0].birthYear == 1991

block:
  let s = """{"known":1,"skip":9999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999}"""
  let a = fromJson(s, LenientKnown)
  assert a.known == 1
block:
  let s = """{"known":1,"skip":[9999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999],"known":2}"""
  let a = fromJson(s, LenientKnown)
  assert a.known == 2
block:
  doAssertRaises(JsonParsingError):
    discard fromJson("""{"known":1,"skip":2}""", LenientKnown,
      ufReject)
block:
  doAssertRaises(JsonParsingError):
    discard fromJson("""{"child":{"known":1,"skip":2}}""", NestedKnown,
      ufReject)
block:
  let s = streams.open("""[{"known":1,"skip":2}]""")
  doAssertRaises(JsonParsingError):
    for value in jsonItems(s, LenientKnown, ufReject):
      discard value
block:
  doAssertRaises(JsonParsingError):
    discard fromJson("""{"known":1,"skip":truX}""", LenientKnown)
