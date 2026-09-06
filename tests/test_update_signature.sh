#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
fixture_dir=$(mktemp -d)
trap 'rm -rf "$fixture_dir"' EXIT

# Generate an isolated test key and archive; no release secrets are needed.
swift - "$fixture_dir" <<'SWIFT'
import CryptoKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let key = Curve25519.Signing.PrivateKey()
let archive = Data("Test update archive".utf8)
let signature = try key.signature(for: archive).base64EncodedString()
try archive.write(to: root.appendingPathComponent("update.dmg"))
let contents = root.appendingPathComponent("vibe hud.app/Contents")
try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
let plist = ["CFBundleVersion": "24", "CFBundleShortVersionString": "1.3.25",
             "SUPublicEDKey": key.publicKey.rawRepresentation.base64EncodedString()]
try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    .write(to: contents.appendingPathComponent("Info.plist"))
try """
<?xml version="1.0"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
<enclosure url="https://github.com/section9-lab/vibe-hud/releases/download/v1.3.25/vibe-hud-v1.3.25.dmg"
sparkle:version="24" sparkle:shortVersionString="1.3.25" sparkle:edSignature="\(signature)"
length="\(archive.count)" type="application/x-apple-diskimage" />
</item></channel></rss>
""".write(to: root.appendingPathComponent("appcast.xml"), atomically: true, encoding: .utf8)
SWIFT

if ! swift "$repo_root/scripts/verify-update.swift" "$fixture_dir/vibe hud.app" "$fixture_dir/update.dmg" "$fixture_dir/appcast.xml"; then
    echo "A correctly signed update must pass verification" >&2
    exit 1
fi

python3 - "$fixture_dir" <<'PY'
from pathlib import Path
import plistlib
import base64
import shutil
import sys
import xml.etree.ElementTree as ET

root = Path(sys.argv[1])
namespace = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
for case in ("tampered", "unsigned", "missing-key", "wrong-key", "wrong-length", "wrong-version", "wrong-url"):
    target = root / case
    target.mkdir()
    shutil.copytree(root / "vibe hud.app", target / "vibe hud.app")
    shutil.copy(root / "update.dmg", target / "update.dmg")
    tree = ET.parse(root / "appcast.xml")
    enclosure = tree.find("./channel/item/enclosure")
    if case == "tampered":
        (target / "update.dmg").write_bytes(b"X" + (root / "update.dmg").read_bytes()[1:])
    elif case == "unsigned":
        del enclosure.attrib[namespace + "edSignature"]
    elif case in ("missing-key", "wrong-key"):
        path = target / "vibe hud.app/Contents/Info.plist"
        info = plistlib.loads(path.read_bytes())
        if case == "missing-key":
            del info["SUPublicEDKey"]
        else:
            info["SUPublicEDKey"] = base64.b64encode(bytes(32)).decode()
        path.write_bytes(plistlib.dumps(info))
    elif case == "wrong-length":
        enclosure.set("length", "1")
    elif case == "wrong-version":
        enclosure.set(namespace + "version", "1")
    else:
        enclosure.set("url", "https://example.com/wrong.dmg")
    tree.write(target / "appcast.xml", encoding="utf-8", xml_declaration=True, default_namespace=None)
PY

for case in tampered unsigned missing-key wrong-key wrong-length wrong-version wrong-url; do
    if swift "$repo_root/scripts/verify-update.swift" "$fixture_dir/$case/vibe hud.app" "$fixture_dir/$case/update.dmg" "$fixture_dir/$case/appcast.xml" > "$fixture_dir/$case.log" 2>&1; then
        echo "Verification must reject $case updates" >&2
        exit 1
    fi
done
echo "Update signature checks passed (valid archive and 7 rejection cases)"
