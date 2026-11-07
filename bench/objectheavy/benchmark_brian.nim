import std/[options, os]
import brian

const RecordCount = 200

type
  State = enum queued, active, closed
  Role = enum user, assistant
  Owner = object
    handle: string
    display: string
    verified: bool
    alias: Option[string]
  Message = object
    role: Role
    content: string
    tags: seq[string]
  Attachment = object
    name: string
    media: string
    url: string
  Record = object
    id: string
    state: State
    title: string
    summary: string
    labels: seq[string]
    owner: Owner
    messages: seq[Message]
    attachments: seq[Attachment]
    enabled: bool

let payload = readFile(currentSourcePath().parentDir() / "objectheavy_payload.json")
let records = fromJson(payload, seq[Record])

doAssert records.len == RecordCount
var checksum = 0
for record in records:
  checksum += record.id.len + record.title.len + record.summary.len
  checksum += record.owner.handle.len + record.owner.display.len
  checksum += record.labels.len + record.messages.len + record.attachments.len
  for message in record.messages:
    checksum += message.content.len + message.tags.len
echo checksum
