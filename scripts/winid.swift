// Prints the id of the largest on-screen window owned by a pid (used by make-screenshots.sh for screencapture -l).
import CoreGraphics
import Foundation

let pid = Int32(CommandLine.arguments[1])!
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
var best: (id: Int, area: Double) = (0, 0)
for w in list where (w[kCGWindowOwnerPID as String] as? Int32) == pid {
    let b = w[kCGWindowBounds as String] as! [String: Any]
    let area = (b["Width"] as! Double) * (b["Height"] as! Double)
    if area > best.area { best = (w[kCGWindowNumber as String] as! Int, area) }
}
print(best.id)
