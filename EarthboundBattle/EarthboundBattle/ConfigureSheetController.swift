import Cocoa
import ScreenSaver

// The "Options…" sheet shown in System Settings → Screen Saver. Built
// programmatically (no .xib) to keep everything in code. Two settings:
//   • Randomize interval (seconds): how often a new background pair is chosen.
//   • Frameskip: animation speed (how far the time tick advances per frame).
final class ConfigureSheetController: NSObject {
    let window: NSWindow
    private let defaultsName: String

    private let intervalField = NSTextField()
    private let intervalStepper = NSStepper()
    private let frameSkipField = NSTextField()
    private let frameSkipStepper = NSStepper()

    private static let intervalMin = 3, intervalMax = 120
    private static let frameSkipMin = 1, frameSkipMax = 10

    init(defaultsName: String) {
        self.defaultsName = defaultsName
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 180),
                          styleMask: [.titled], backing: .buffered, defer: true)
        super.init()
        window.title = "Earthbound Battle Backgrounds"
        buildUI()
        loadValues()
    }

    private func defaults() -> ScreenSaverDefaults? {
        ScreenSaverDefaults(forModuleWithName: defaultsName)
    }

    private func buildUI() {
        guard let content = window.contentView else { return }

        let intervalLabel = makeLabel("New background every (seconds):", frame: NSRect(x: 20, y: 132, width: 240, height: 20))
        content.addSubview(intervalLabel)

        intervalField.frame = NSRect(x: 268, y: 130, width: 50, height: 22)
        intervalField.alignment = .right
        content.addSubview(intervalField)

        intervalStepper.frame = NSRect(x: 322, y: 128, width: 19, height: 27)
        intervalStepper.minValue = Double(Self.intervalMin)
        intervalStepper.maxValue = Double(Self.intervalMax)
        intervalStepper.increment = 1
        intervalStepper.valueWraps = false
        intervalStepper.target = self
        intervalStepper.action = #selector(intervalStepperChanged)
        content.addSubview(intervalStepper)

        let frameSkipLabel = makeLabel("Animation speed (1 = slow, 10 = fast):", frame: NSRect(x: 20, y: 92, width: 240, height: 20))
        content.addSubview(frameSkipLabel)

        frameSkipField.frame = NSRect(x: 268, y: 90, width: 50, height: 22)
        frameSkipField.alignment = .right
        content.addSubview(frameSkipField)

        frameSkipStepper.frame = NSRect(x: 322, y: 88, width: 19, height: 27)
        frameSkipStepper.minValue = Double(Self.frameSkipMin)
        frameSkipStepper.maxValue = Double(Self.frameSkipMax)
        frameSkipStepper.increment = 1
        frameSkipStepper.valueWraps = false
        frameSkipStepper.target = self
        frameSkipStepper.action = #selector(frameSkipStepperChanged)
        content.addSubview(frameSkipStepper)

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.frame = NSRect(x: 196, y: 18, width: 84, height: 32)
        cancelButton.bezelStyle = .rounded
        content.addSubview(cancelButton)

        let okButton = NSButton(title: "OK", target: self, action: #selector(ok))
        okButton.frame = NSRect(x: 284, y: 18, width: 84, height: 32)
        okButton.bezelStyle = .rounded
        okButton.keyEquivalent = "\r"
        content.addSubview(okButton)
    }

    private func makeLabel(_ text: String, frame: NSRect) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.frame = frame
        return label
    }

    private func loadValues() {
        let d = defaults()
        let interval = d?.integer(forKey: EarthboundBattleView.intervalKey) ?? 10
        let frameSkip = d?.integer(forKey: EarthboundBattleView.frameSkipKey) ?? 1
        let clampedInterval = min(max(interval == 0 ? 10 : interval, Self.intervalMin), Self.intervalMax)
        let clampedFrameSkip = min(max(frameSkip == 0 ? 1 : frameSkip, Self.frameSkipMin), Self.frameSkipMax)
        intervalField.integerValue = clampedInterval
        intervalStepper.integerValue = clampedInterval
        frameSkipField.integerValue = clampedFrameSkip
        frameSkipStepper.integerValue = clampedFrameSkip
    }

    @objc private func intervalStepperChanged() {
        intervalField.integerValue = intervalStepper.integerValue
    }

    @objc private func frameSkipStepperChanged() {
        frameSkipField.integerValue = frameSkipStepper.integerValue
    }

    @objc private func ok() {
        let interval = min(max(intervalField.integerValue, Self.intervalMin), Self.intervalMax)
        let frameSkip = min(max(frameSkipField.integerValue, Self.frameSkipMin), Self.frameSkipMax)
        let d = defaults()
        d?.set(interval, forKey: EarthboundBattleView.intervalKey)
        d?.set(frameSkip, forKey: EarthboundBattleView.frameSkipKey)
        d?.synchronize()
        dismiss()
    }

    @objc private func cancel() {
        loadValues() // discard edits
        dismiss()
    }

    private func dismiss() {
        if let parent = window.sheetParent {
            parent.endSheet(window)
        } else {
            window.orderOut(nil)
        }
    }
}
