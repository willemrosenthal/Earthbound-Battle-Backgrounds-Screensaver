import Cocoa
import ScreenSaver

// The "Options…" sheet shown in System Settings → Screen Saver. Built
// programmatically (no .xib) to keep everything in code. Settings:
//   • Randomize interval (seconds): how often a new background pair is chosen.
//   • Frameskip: animation speed (how far the time tick advances per frame).
//   • Disabled backgrounds: a grid of every background (1…326) with a checkbox
//     each; unchecked entries are excluded from the random rotation.
final class ConfigureSheetController: NSObject, NSCollectionViewDataSource {
    let window: NSWindow
    private let defaultsName: String

    private let intervalField = NSTextField()
    private let intervalStepper = NSStepper()
    private let frameSkipField = NSTextField()
    private let frameSkipStepper = NSStepper()
    private let saturationSlider = NSSlider()
    private let saturationValueLabel = NSTextField(labelWithString: "")
    private var collectionView: NSCollectionView!
    private var animationTimer: Timer?

    // Working copy of disabled indices; committed to defaults only on OK.
    private var disabled: Set<Int> = []

    private static let intervalMin = 3, intervalMax = 120
    private static let frameSkipMin = 1, frameSkipMax = 10
    private static let saturationMin = 1.0, saturationMax = 3.0
    // Backgrounds shown in the grid. Index 0 is the "blank" background and is not
    // selectable — it's always available as the solo-layer partner.
    private static let firstIndex = 1
    private static let backgroundCount = Rom.entryCount - 1 // 326 toggleable entries

    init(defaultsName: String) {
        self.defaultsName = defaultsName
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 680),
                          styleMask: [.titled, .resizable], backing: .buffered, defer: true)
        window.minSize = NSSize(width: 480, height: 420)
        super.init()
        window.title = "Earthbound Battle Backgrounds"
        buildUI()
        loadValues()
        startAnimating()
    }

    deinit {
        animationTimer?.invalidate()
    }

    // Animates the previews currently on screen. Each frame re-renders only the
    // visible cells (~20–40), and the work is skipped entirely while the Options
    // window is hidden, so it costs nothing when the sheet isn't up.
    private func startAnimating() {
        let timer = Timer(timeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            guard let self = self, self.window.isVisible else { return }
            for item in self.collectionView.visibleItems() {
                (item as? BackgroundThumbnailItem)?.renderFrame()
            }
        }
        // .common so it keeps firing during modal/tracking run-loop modes.
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    private func defaults() -> ScreenSaverDefaults? {
        ScreenSaverDefaults(forModuleWithName: defaultsName)
    }

    private func buildUI() {
        guard let content = window.contentView else { return }
        let W = content.bounds.width

        // --- Bottom band: settings + buttons (pinned to the bottom) ---

        let intervalLabel = makeLabel("New background every (seconds):", frame: NSRect(x: 20, y: 92, width: 240, height: 20))
        content.addSubview(intervalLabel)

        intervalField.frame = NSRect(x: 268, y: 90, width: 50, height: 22)
        intervalField.alignment = .right
        content.addSubview(intervalField)

        intervalStepper.frame = NSRect(x: 322, y: 88, width: 19, height: 27)
        intervalStepper.minValue = Double(Self.intervalMin)
        intervalStepper.maxValue = Double(Self.intervalMax)
        intervalStepper.increment = 1
        intervalStepper.valueWraps = false
        intervalStepper.target = self
        intervalStepper.action = #selector(intervalStepperChanged)
        content.addSubview(intervalStepper)

        let frameSkipLabel = makeLabel("Animation speed (1 = slow, 10 = fast):", frame: NSRect(x: 20, y: 56, width: 240, height: 20))
        content.addSubview(frameSkipLabel)

        frameSkipField.frame = NSRect(x: 268, y: 54, width: 50, height: 22)
        frameSkipField.alignment = .right
        content.addSubview(frameSkipField)

        frameSkipStepper.frame = NSRect(x: 322, y: 52, width: 19, height: 27)
        frameSkipStepper.minValue = Double(Self.frameSkipMin)
        frameSkipStepper.maxValue = Double(Self.frameSkipMax)
        frameSkipStepper.increment = 1
        frameSkipStepper.valueWraps = false
        frameSkipStepper.target = self
        frameSkipStepper.action = #selector(frameSkipStepperChanged)
        content.addSubview(frameSkipStepper)

        let saturationLabel = makeLabel("Color saturation:", frame: NSRect(x: 20, y: 124, width: 130, height: 20))
        content.addSubview(saturationLabel)

        saturationSlider.frame = NSRect(x: 150, y: 122, width: 150, height: 22)
        saturationSlider.minValue = Self.saturationMin
        saturationSlider.maxValue = Self.saturationMax
        saturationSlider.isContinuous = true
        saturationSlider.target = self
        saturationSlider.action = #selector(saturationChanged)
        content.addSubview(saturationSlider)

        saturationValueLabel.frame = NSRect(x: 308, y: 124, width: 60, height: 20)
        content.addSubview(saturationValueLabel)

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.frame = NSRect(x: W - 184, y: 16, width: 84, height: 32)
        cancelButton.bezelStyle = .rounded
        cancelButton.autoresizingMask = [.minXMargin]
        content.addSubview(cancelButton)

        let okButton = NSButton(title: "OK", target: self, action: #selector(ok))
        okButton.frame = NSRect(x: W - 96, y: 16, width: 84, height: 32)
        okButton.bezelStyle = .rounded
        okButton.keyEquivalent = "\r"
        okButton.autoresizingMask = [.minXMargin]
        content.addSubview(okButton)

        let enableAll = NSButton(title: "Enable All", target: self, action: #selector(enableAll))
        enableAll.frame = NSRect(x: 20, y: 16, width: 96, height: 32)
        enableAll.bezelStyle = .rounded
        content.addSubview(enableAll)

        let disableAll = NSButton(title: "Disable All", target: self, action: #selector(disableAll))
        disableAll.frame = NSRect(x: 120, y: 16, width: 96, height: 32)
        disableAll.bezelStyle = .rounded
        content.addSubview(disableAll)

        let hint = makeLabel("Uncheck backgrounds to exclude them from the random rotation:",
                             frame: NSRect(x: 20, y: 158, width: W - 40, height: 18))
        hint.autoresizingMask = [.width]
        content.addSubview(hint)

        // --- Top: the scrollable thumbnail grid (grows with the window) ---

        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 96, height: 112)
        layout.minimumInteritemSpacing = 12
        layout.minimumLineSpacing = 12
        layout.sectionInset = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

        collectionView = NSCollectionView()
        collectionView.collectionViewLayout = layout
        collectionView.dataSource = self
        collectionView.isSelectable = false
        collectionView.backgroundColors = [.clear]
        collectionView.register(BackgroundThumbnailItem.self, forItemWithIdentifier: BackgroundThumbnailItem.identifier)

        let scroll = NSScrollView(frame: NSRect(x: 16, y: 184, width: W - 32, height: 680 - 184 - 16))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.autohidesScrollers = true
        scroll.documentView = collectionView
        scroll.autoresizingMask = [.width, .height]
        content.addSubview(scroll)
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

        let disabledList = d?.array(forKey: EarthboundBattleView.disabledKey) as? [Int] ?? []
        disabled = Set(disabledList)

        let sat = d?.double(forKey: EarthboundBattleView.saturationKey) ?? 1
        saturationSlider.doubleValue = min(max(sat < 1 ? 1 : sat, Self.saturationMin), Self.saturationMax)
        applySaturationValue(saturationSlider.doubleValue)

        collectionView?.reloadData()
    }

    @objc private func intervalStepperChanged() {
        intervalField.integerValue = intervalStepper.integerValue
    }

    @objc private func saturationChanged() {
        applySaturationValue(saturationSlider.doubleValue)
    }

    // Updates the readout and the live preview saturation as the slider moves.
    private func applySaturationValue(_ value: Double) {
        let v = min(max(value, Self.saturationMin), Self.saturationMax)
        saturationValueLabel.stringValue = String(format: "%.1f×", v)
        BackgroundThumbnailItem.previewSaturation = v
    }

    @objc private func frameSkipStepperChanged() {
        frameSkipField.integerValue = frameSkipStepper.integerValue
    }

    @objc private func enableAll() {
        disabled.removeAll()
        collectionView.reloadData()
    }

    @objc private func disableAll() {
        disabled = Set(Self.firstIndex..<Rom.entryCount)
        collectionView.reloadData()
    }

    @objc private func ok() {
        let interval = min(max(intervalField.integerValue, Self.intervalMin), Self.intervalMax)
        let frameSkip = min(max(frameSkipField.integerValue, Self.frameSkipMin), Self.frameSkipMax)
        let d = defaults()
        d?.set(interval, forKey: EarthboundBattleView.intervalKey)
        d?.set(frameSkip, forKey: EarthboundBattleView.frameSkipKey)
        d?.set(disabled.sorted(), forKey: EarthboundBattleView.disabledKey)
        let saturation = min(max(saturationSlider.doubleValue, Self.saturationMin), Self.saturationMax)
        d?.set(saturation, forKey: EarthboundBattleView.saturationKey)
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

    // MARK: - NSCollectionViewDataSource

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        Self.backgroundCount
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: BackgroundThumbnailItem.identifier, for: indexPath) as! BackgroundThumbnailItem
        let index = indexPath.item + Self.firstIndex
        item.configure(index: index, enabled: !disabled.contains(index)) { [weak self] idx, enabled in
            guard let self = self else { return }
            if enabled { self.disabled.remove(idx) } else { self.disabled.insert(idx) }
        }
        return item
    }
}
