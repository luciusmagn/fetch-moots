/*

 Look, ma!

 This is the first program written in D since 2008!

 2025 is gonna be D's year, I promise :)

*/


import std.stdio;
import std.file;
import std.path;
import std.array;
import std.algorithm;
import std.conv;
import std.json;
import std.parallelism;
import requests;
import asdf;

/* It's like what if we made C++ more like Java,
   but less verbose
*/

struct UserInfo {
    string username;
    string profile_image_url;
}

UserInfo[] processFollowersFile(string filePath) {
    auto jsonData = filePath.readText.parseJSON;
    auto instructions = jsonData["data"]["user"]["result"]["timeline"]["timeline"]["instructions"].array;

    UserInfo[] mutuals;
    foreach (instruction; instructions) {
        if ("entries" !in instruction) continue;
        auto entries = instruction["entries"].array;
        foreach (entry; entries) {
            if (entry["content"]["entryType"].str != "TimelineTimelineItem") continue;
            auto user = entry["content"]["itemContent"]["user_results"]["result"]["legacy"];
            if (user["followed_by"].boolean && user["following"].boolean) {

                // if you don't know D, would you know what the following syntax does?

                mutuals ~= UserInfo(
                    user["screen_name"].str,
                    user["profile_image_url_https"].str.replace("_normal", "")
                );
            }
        }
    }

    // imma be real chief, writefln is a weird name, but at least
    // it works pretty well
    //
    // I hate that it needs the C-like format specifiers, though
    writefln("Found %d mutuals in %s", mutuals.length, filePath);
    return mutuals;
}

void downloadProfilePicture(UserInfo user, string folder) {
    // auto is such a C++-ism
    auto client = Request();
    auto response = client.get(user.profile_image_url);

    if (response.code == 200) {
        if (!folder.exists) mkdir(folder);
        auto fileExtension = user.profile_image_url.split(".")[$-1];
        auto filePath = buildPath(folder, user.username ~ "." ~ fileExtension);
        std.file.write(filePath, response.responseBody.data);
        writefln("Downloaded profile picture for @%s", user.username);
    } else {
        writefln("Failed to download profile picture for @%s", user.username);
    }
}

void main(string[] args) {
    if (args.length < 2) {
        writeln("Usage: fetch_moots [FILES] --folder OUTPUT_FOLDER");
        return;
    }

    string folder = "mutuals";
    string[] files;

    // at least we have civilized foreach
    foreach (arg; args[1..$]) {
        if (arg.startsWith("--folder=")) {
            folder = arg["--folder=".length .. $];
        } else {
            files ~= arg;
        }
    }

    UserInfo[] allMutuals;
    foreach (file; files) {
        allMutuals ~= processFollowersFile(file);
    }

    foreach (mutual; parallel(allMutuals)) {
        downloadProfilePicture(mutual, folder);
    }

    writefln("Finished downloading %d profile pictures to %s", allMutuals.length, folder);
}

// Probably a person will have an easier time doing things in D
// than in either C or C++, what I mean is practical things and
// web-dev/gui/network-related stuff.
//
// But hmmm, it could be bolder
