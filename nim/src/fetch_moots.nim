import std/[os, json, strutils, sequtils, asyncdispatch, httpclient, options, tables]
import cligen, jsony

type
  UserInfo = object
    username: string
    profile_image_url: string

proc extractUserInfo(entry: JsonNode): Option[UserInfo] =
  let user = entry["content"]["itemContent"]["user_results"]["result"]["legacy"]
  let isMutual = user["followed_by"].getBool and user["following"].getBool
  if isMutual:
    some(UserInfo(
      username: user["screen_name"].getStr,
      profile_image_url: user["profile_image_url_https"].getStr.replace(
          "_normal", "")
    ))
  else:
    none(UserInfo)

proc findAllEntries(instructions: JsonNode): seq[JsonNode] =
  for instruction in instructions:
    for value in instruction.fields.values:
      if value.kind == JArray:
        result.add value.elems.filterIt(it.kind == JObject and "entryId" in it)

proc processFollowersFile(filePath: string): seq[UserInfo] =
  let content = readFile(filePath)
  let data = content.fromJson
  let instructions = data["data"]["user"]["result"]["timeline"]["timeline"]["instructions"]
  let entries = findAllEntries(instructions)

  result = entries.filterIt(it["content"]["entryType"].getStr == "TimelineTimelineItem")
    .mapIt(extractUserInfo(it))
    .filterIt(it.isSome)
    .mapIt(it.get)

  echo "Found ", result.len, " mutuals in ", filePath

proc downloadProfilePicture(user: UserInfo, folder: string) {.async.} =
  let client = newAsyncHttpClient()
  let response = await client.get(user.profile_image_url)

  if response.code.is2xx:
    let content = await response.body
    let fileExtension = user.profile_image_url.split(".")[^1]
    let filename = user.username & "." & fileExtension
    let filepath = folder / filename

    createDir(folder)
    writeFile(filepath, content)
    echo "Downloaded profile picture for @", user.username
  else:
    echo "Failed to download profile picture for @", user.username

  client.close()

proc main(files: seq[string], folder = "mutuals") =
  var allMutuals: seq[UserInfo]
  for file in files:
    allMutuals.add processFollowersFile(file)

  var futures: seq[Future[void]]
  for mutual in allMutuals:
    futures.add downloadProfilePicture(mutual, folder)

  waitFor all(futures)

  echo "Finished downloading ", allMutuals.len, " profile pictures to ", folder

when isMainModule:
  dispatch main
