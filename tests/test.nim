import jsonx, std/[enumerate, math, options, sets, tables]
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

proc readJson(dst: var Baz; p: var JsonParser) =
  var tmp: string
  readJson(tmp, p)
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
  let data = "hello world"
  let a = jsonToFromString(data)
  assert a == data
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
  let s = streams.open("""{"va_l": {"vaLue": "stuff"}}""")
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
    assert a[0].name == "John Smith"
    assert a[0].gender == male
    assert a[0].siblings.len == 2
    assert a[0].siblings[0].birthYear == 1991
