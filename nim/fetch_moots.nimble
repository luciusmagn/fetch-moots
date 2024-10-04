# Package

version       = "0.1.0"
author        = "Lukáš Hozda"
description   = "Fetch the pics of your mutuals on Twitter aka X the everything app"
license       = "Fair"
srcDir        = "src"
bin           = @["fetch_moots"]


# Dependencies

requires "nim >= 2.0.8"
requires "cligen"
requires "jsony"
