import AppKit
import Carbon

func sourceID() -> String {
    let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    guard let value = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "" }
    return Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String
}
let workspace = NSWorkspace.shared
let originalApp = workspace.frontmostApplication
let originalSource = sourceID()
let targets = [("com.hnc.Discord", "com.apple.inputmethod.TCIM.Pinyin"),
               ("com.tencent.xinWeChat", "com.apple.inputmethod.SCIM.ITABC")]
var passed = true
for round in 1...3 {
    for (id, expected) in targets {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first else {
            print("MISSING \(id)"); exit(2)
        }
        app.activate(options: [])
        for sample in 1...4 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            let front = workspace.frontmostApplication?.bundleIdentifier ?? ""
            let actual = sourceID()
            print("round=\(round) t=\(Double(sample)*0.5) front=\(front) source=\(actual) expected=\(expected)")
            fflush(stdout)
            if sample == 4 && (front != id || actual != expected) { passed = false }
        }
    }
}
originalApp?.activate(options: [])
RunLoop.current.run(until: Date().addingTimeInterval(0.5))
let all = TISCreateInputSourceList(nil, false).takeRetainedValue() as! [TISInputSource]
if let original = all.first(where: {
    guard let raw = TISGetInputSourceProperty($0, kTISPropertyInputSourceID) else { return false }
    return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String == originalSource
}) { TISSelectInputSource(original) }
print(passed ? "PASS" : "FAIL")
exit(passed ? 0 : 1)
