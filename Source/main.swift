// Copyright 2019 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import OpenLocationCode
import Swifter
import Dispatch
import SwiftyJSON
import Glibc
import Foundation

// Disable stdout buffer (https://stackoverflow.com/a/28180452/72176)
setbuf(stdout, nil);

func logRequest(_ request: HttpRequest) {
  print("\nHandling request: \(request.params as AnyObject)")
}

let server = HttpServer()

server.middleware.append { request in
  print("\nHandling request: \(request.path)")
  return nil
}


// Root path, show help text
server["/"] = { request in
  return HttpResponse.ok(.html("Usage: <code>/degrees/[lat],[lng]</code>, e.g. <a href=\"/degrees/32,34\">/degrees/32,34</a>"))
}

// Convert latitude and longitude decimal degrees to plus code
server["/degrees/:latlng"] = { request in
  logRequest(request)

  // URL param
  var latlng = request.params[":latlng"] ?? ""
  if latlng == "" {
    latlng = "37.444796, -122.161538"
  }
  latlng = latlng.filter { "+-,.0123456789".contains($0) }

  // Extract Latitude & Longitude
  let params = latlng.split{$0 == ","}
  if params.count != 2 {
    return HttpResponse.notFound
  }

  let lat = Double(params[0])!
  let lng = params.count > 1 ? Double(params[1])! : 0
  print(String(format:"Converting: %f %f", lat, lng))

  // Response dictionary
  var dict = ["docs": "https://plus.codes"] as [String: Any?]
  dict["latitude"] = lat
  dict["longitude"] = lng

  // Encode as a Plus Code
  if let code = OpenLocationCode.encode(latitude: lat,
                                        longitude: lng,
                                        codeLength: 10) {
    print("Open Location Code: \(code)")
    dict["status"] = "ok"
    dict["pluscode"] = code
  } else {
    dict["status"] = "error"
  }

  var json = JSON(dict).rawString() ?? "error"
  json = json.replacingOccurrences(of: "\\/", with: "/")

  return HttpResponse.ok(.text(json))
}

// Health and Readiness endpoints for Kubernetes
server["/healthz"] = { request in
  logRequest(request)
  return HttpResponse.ok(.text("ok"))
}
server["/readyz"] = { request in
  logRequest(request)
  // 
  return HttpResponse.ok(.text("ok"))
}

// Calculate Pi (demonstration of a CPU intensive task)
server["/pi"] = { request in
  logRequest(request)

  var piDiv4: Double = 1
  var odd: UInt = 3
  for _ in 0...100000000 {
    piDiv4 -= 1.0/Double(odd)
    piDiv4 += 1.0/(Double(odd+2))
    odd += 4
  }

  return HttpResponse.ok(.text(String(format: "%f", (piDiv4*4))))
}

// Download remote file
server["/remote"] = { request in

  var file: String?
  do {
      file = try String(contentsOf: URL(string: "http://www.google.com/robots.txt")!)
  } catch {
      let errorMsg = ("Download error: \(error).")
      print(errorMsg)
      return HttpResponse.ok(.text(errorMsg))
  }

  if let robots = file {
    return HttpResponse.ok(.text(robots))
  }
  return HttpResponse.ok(.text("Unexpected error"))
}

// Start the server & wait for connections
let semaphore = DispatchSemaphore(value: 0)
do {
  print ("Boot started")
  //  sleep(8) // artificial delay to simulate startup time
  try server.start(80, forceIPv4: true)
  print("Server has started on port \(try server.port())...")
  semaphore.wait()
} catch {
  print("Server start error: \(error)")
  semaphore.signal()
}

