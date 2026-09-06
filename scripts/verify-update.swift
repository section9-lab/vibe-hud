import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("Update verification failed: \(message)\n".utf8))
    exit(1)
}

guard CommandLine.arguments.count == 4 else {
    fail("Usage: verify-update.swift <app> <archive> <appcast>")
}

do {
    let app = URL(fileURLWithPath: CommandLine.arguments[1])
    let archive = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
    let infoData = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
    guard let info = try PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any],
          let publicKey = info["SUPublicEDKey"] as? String,
          let keyData = Data(base64Encoded: publicKey),
          let version = info["CFBundleShortVersionString"] as? String,
          let build = info["CFBundleVersion"] as? String else {
        fail("The built app must contain its public key and version")
    }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
    let feed = try XMLDocument(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]))
    let enclosures = try feed.nodes(forXPath: "/rss/channel/item/enclosure")
    guard enclosures.count == 1, let enclosure = enclosures.first as? XMLElement else {
        fail("Expected one release enclosure")
    }
    let namespace = "http://www.andymatuschak.org/xml-namespaces/sparkle"
    guard let signature = enclosure.attribute(forLocalName: "edSignature", uri: namespace)?.stringValue,
          let signatureData = Data(base64Encoded: signature),
          key.isValidSignature(signatureData, for: archive) else {
        fail("The archive signature does not match the public key in the built app")
    }
    guard enclosure.attribute(forName: "length")?.stringValue == String(archive.count),
          enclosure.attribute(forLocalName: "version", uri: namespace)?.stringValue == build,
          enclosure.attribute(forLocalName: "shortVersionString", uri: namespace)?.stringValue == version,
          enclosure.attribute(forName: "url")?.stringValue == "https://github.com/section9-lab/vibe-hud/releases/download/v\(version)/vibe-hud-v\(version).dmg" else {
        fail("The appcast length, version, or download URL does not match the release")
    }
    print("Verified update signature and metadata for v\(version) (\(build))")
} catch {
    fail(error.localizedDescription)
}
