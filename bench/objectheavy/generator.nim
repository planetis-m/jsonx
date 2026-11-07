import std/os

const RecordCount = 200

proc addRecord(output: var string; index: int) =
  let state = ["queued", "active", "closed"][index mod 3]
  output.add "{\"id\":\"record_"
  output.add $index
  output.add "\",\"state\":\""
  output.add state
  output.add "\",\"title\":\"Support request for workspace "
  output.add $index
  output.add "\",\"summary\":\"A concise description with ordinary text.\","
  output.add "\"labels\":[\"support\",\"priority\",\"review\"],"
  output.add "\"owner\":{\"handle\":\"owner_"
  output.add $index
  output.add "\",\"display\":\"Owner Display\",\"verified\":true"
  if index mod 2 == 0:
    output.add ",\"alias\":\"primary-owner\""
  output.add "},\"messages\":["
  output.add "{\"role\":\"user\",\"content\":\"Please inspect the request.\\nIt needs a reply.\","
  output.add "\"tags\":[\"incoming\",\"review\"]},"
  output.add "{\"role\":\"assistant\",\"content\":\"Acknowledged: \\\"safe\\\" unicode \\u03b1.\","
  output.add "\"tags\":[\"response\",\"internal\"]}],"
  output.add "\"attachments\":[{\"name\":\"notes.txt\",\"media\":\"text/plain\","
  output.add "\"url\":\"https://example.invalid/notes\"},{\"name\":\"image.png\","
  output.add "\"media\":\"image/png\",\"url\":\"https://example.invalid/image\"}],"
  output.add "\"enabled\":true,\"extension\":{\"workflow\":{\"steps\":[\"inspect\","
  output.add "\"route\"],\"flags\":[true,false,null]},\"opaque\":[\"alpha\","
  output.add "{\"kind\":\"plugin\",\"values\":[\"x\",\"y\"]}]}}"

var payload = newStringOfCap(RecordCount * 1_200)
payload.add '['
for index in 0..<RecordCount:
  if index > 0: payload.add ','
  payload.addRecord(index)
payload.add ']'
writeFile(currentSourcePath().parentDir() / "objectheavy_payload.json", payload)
