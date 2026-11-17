import Foundation
let fm = FileManager.default
let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try fm.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: root) }
let src = root.appendingPathComponent("source")
try fm.createDirectory(at: src.appendingPathComponent("Documents"), withIntermediateDirectories: true)
try fm.createDirectory(at: src.appendingPathComponent("Library/Preferences"), withIntermediateDirectories: true)
try fm.createDirectory(at: src.appendingPathComponent("Library/Caches"), withIntermediateDirectories: true)
try fm.createDirectory(at: src.appendingPathComponent("tmp"), withIntermediateDirectories: true)
let bytes = Data([0, 1, 255, 7])
try bytes.write(to: src.appendingPathComponent("Documents/important.bin"))
try bytes.write(to: src.appendingPathComponent("Library/Preferences/settings.plist"))
try bytes.write(to: src.appendingPathComponent("Library/Caches/cache"))
try bytes.write(to: src.appendingPathComponent("tmp/transient"))
let metadata = src.appendingPathComponent(AppDataCopy.metadataName)
try bytes.write(to: metadata)
try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: metadata.path)
let dest = root.appendingPathComponent("backup")
let result = try AppDataCopy.copy(source: src, to: dest, applicationContainer: true)
precondition(result.copiedFiles == 2)
let actualDocument = try Data(contentsOf: dest.appendingPathComponent("Documents/important.bin"))
precondition(actualDocument == bytes)
let actualPreferences = try Data(contentsOf: dest.appendingPathComponent("Library/Preferences/settings.plist"))
precondition(actualPreferences == bytes)
precondition(!fm.fileExists(atPath: dest.appendingPathComponent(AppDataCopy.metadataName).path))
precondition(!fm.fileExists(atPath: dest.appendingPathComponent("Library/Caches").path))
precondition(!fm.fileExists(atPath: dest.appendingPathComponent("tmp").path))
precondition(result.excluded.contains(AppDataCopy.metadataName))
precondition(result.excluded.contains("Library/Caches"))
// Actual user-data failures must remain failures, rather than successful incomplete backups.
let locked = src.appendingPathComponent("Documents/unreadable")
try bytes.write(to: locked)
try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
var failed = false
do { _ = try AppDataCopy.copy(source: src, to: root.appendingPathComponent("failed"), applicationContainer: true) }
catch { failed = true }
precondition(failed, "Unreadable user data must abort")
try fm.removeItem(at: locked)
try fm.createSymbolicLink(atPath: src.appendingPathComponent("Documents/outside").path, withDestinationPath: "/etc")
failed = false
do { _ = try AppDataCopy.copy(source: src, to: root.appendingPathComponent("links"), applicationContainer: true) }
catch { failed = true }
precondition(failed, "Links must not traverse outside the selected data")
print("PASS: protected metadata excluded; Documents/Library preserved; cache/tmp excluded; unreadable data and symlinks abort.")
