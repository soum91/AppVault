"""Catalog the upstream DLiPA release, using metadata read from its actual IPA.
This references the upstream asset; it does not repackage or rebrand DLiPA.
"""
import base64, hashlib, io, json, os, plistlib, subprocess, urllib.request, zipfile

upstream = "AhmedBafkir/DLiPA"
release = json.loads(subprocess.check_output(["gh", "api", f"repos/{upstream}/releases/latest"]))
assets = [a for a in release["assets"] if a["name"].lower().endswith(".ipa")]
if len(assets) != 1:
    raise RuntimeError("Expected exactly one official IPA asset")
asset = assets[0]
if not asset["browser_download_url"].startswith(f"https://github.com/{upstream}/releases/download/"):
    raise RuntimeError("Unexpected upstream asset URL")
with urllib.request.urlopen(asset["browser_download_url"], timeout=90) as response:
    package = response.read(100 * 1024 * 1024 + 1)
if len(package) != asset["size"] or len(package) > 100 * 1024 * 1024:
    raise RuntimeError("IPA size mismatch or oversized package")
digest = hashlib.sha256(package).hexdigest()
if asset.get("digest") and asset["digest"] != "sha256:" + digest:
    raise RuntimeError("IPA digest mismatch")
with zipfile.ZipFile(io.BytesIO(package)) as archive:
    paths = [n for n in archive.namelist() if n.startswith("Payload/") and n.count("/") == 2 and n.endswith(".app/Info.plist")]
    if len(paths) != 1:
        raise RuntimeError("Expected one main application Info.plist")
    info = plistlib.loads(archive.read(paths[0]))
    bundle = info["CFBundleIdentifier"]
    version = info["CFBundleShortVersionString"]
    build = info["CFBundleVersion"]
    executable = paths[0].rsplit("/", 1)[0] + "/" + info["CFBundleExecutable"]
    if executable not in archive.namelist():
        raise RuntimeError("IPA has no main executable")
    icons = info.get("CFBundleIcons", {}).get("CFBundlePrimaryIcon", {})
    print(json.dumps({"bundleIdentifier": bundle, "version": version, "buildVersion": build,
                      "minimumOS": info.get("MinimumOSVersion"), "size": len(package),
                      "sha256": digest, "packagedIcon": bool(icons)}))
repo = os.environ["GITHUB_REPOSITORY"]
current = json.loads(subprocess.check_output(["gh", "api", f"repos/{repo}/contents/repo.json"]))
feed = json.loads(base64.b64decode(current["content"]))
description = ("Official, unmodified DLiPA by AhmedBafkir. Download and share App Store apps as IPA files "
               "using your Apple Account; supports available older versions. This downloads packages from Apple, "
               "not the installed binary from your phone. Apple account authorization and version availability apply. "
               "Authentication and downloads on iOS 27.0.1 have not been tested by AppVault's maintainer.")
entry = {
    "name": "DLiPA",
    "bundleIdentifier": bundle,
    "developerName": "AhmedBafkir",
    "subtitle": "App Store IPA downloader",
    "localizedDescription": description,
    "version": version,
    "versionDate": release["published_at"][:10],
    "downloadURL": asset["browser_download_url"],
    "size": len(package),
    "versions": [{
        "version": version, "buildVersion": build, "date": release["published_at"][:10],
        "downloadURL": asset["browser_download_url"], "size": len(package),
        "minOSVersion": info.get("MinimumOSVersion", "13.0"),
        "localizedDescription": release["body"]
    }]
}
feed["apps"] = [app for app in feed["apps"] if app.get("bundleIdentifier") != bundle] + [entry]
feed["subtitle"] = "AppVault and official IPA download tools"
feed["description"] = ("DLiPA is a separate third-party App Store IPA downloader. AppVault provides experimental "
                       "data backups and does not extract installed IPA packages on iOS 27.0.1.")
payload = {"message": "Catalog official DLiPA IPA downloader with verified package metadata [skip ci]",
           "sha": current["sha"],
           "content": base64.b64encode((json.dumps(feed, indent=2) + "\n").encode()).decode()}
with open("catalog-request.json", "w") as out:
    json.dump(payload, out)
subprocess.check_call(["gh", "api", "--method", "PUT", f"repos/{repo}/contents/repo.json",
                       "--input", "catalog-request.json"], stdout=subprocess.DEVNULL)
print("Official DLiPA source entry published.")
