import AppKit
import Combine

@MainActor
final class StatusBarController: NSObject {
    private let viewModel: SpaceViewModel
    private let settings: AppSettings
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var cancellables = Set<AnyCancellable>()
    private var renderedSpaceCount = 0
    private var renderedActiveIndex: Int?
    private var renderedIndicatorKinds: [SpaceIndicatorKind] = []
    private var renderedIndicatorIdentifiers: [Int64] = []
    private var isAnimatingStructureChange = false
    private var needsStructureRefresh = false
    private var indicatorView: StatusIndicatorView?
    private var selectedIndicatorColorIndex: Int?

    init(viewModel: SpaceViewModel, settings: AppSettings) {
        self.viewModel = viewModel
        self.settings = settings
        super.init()
        configureStatusItem()
        observeChanges()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.title = ""
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.contentTintColor = nil
        button.toolTip = L10n.string("status.tooltip")
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.rightMouseDown])
        button.setAccessibilityLabel(L10n.string("accessibility.workspaces"))

        updateArtwork(for: viewModel.spaceCount)
        updateActivePill(to: viewModel.activeIndex, animated: false)
        updateToolTip(viewModel.message)
    }

    private func observeChanges() {
        viewModel.$activeIndex
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] index in
                self?.updateActivePill(to: index, animated: true)
                self?.updateAccessibilityValue(index)
            }
            .store(in: &cancellables)

        viewModel.$indicators
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] indicators in
                self?.transitionArtwork(to: indicators)
            }
            .store(in: &cancellables)

        viewModel.$message
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] message in
                self?.updateToolTip(message)
            }
            .store(in: &cancellables)

        settings.$animateIndicator
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] isEnabled in
                guard let self, !isEnabled else { return }
                if let index = self.renderedActiveIndex {
                    self.indicatorView?.setActiveIndex(index, animated: false)
                }
            }
            .store(in: &cancellables)

        settings.$indicatorColors
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateArtwork(for: self.renderedSpaceCount, force: true)
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(
            settings.$indicatorSizeScale,
            settings.$indicatorSpacingScale
        )
        .removeDuplicates { previous, current in
            previous.0 == current.0 && previous.1 == current.1
        }
        .dropFirst()
        .receive(on: RunLoop.main)
        .sink { [weak self] _, _ in
            guard let self else { return }
            self.updateArtwork(for: self.renderedSpaceCount, force: true)
        }
        .store(in: &cancellables)
    }

    private func updateArtwork(for count: Int, force: Bool = false) {
        let count = max(count, 1)
        guard force || count != renderedSpaceCount else { return }
        renderedSpaceCount = count
        renderedIndicatorIdentifiers = viewModel.indicators.map(\.id)
        let kinds = viewModel.indicatorKinds.count == count
            ? viewModel.indicatorKinds
            : (0..<count).map { .desktop(colorIndex: $0) }
        renderedIndicatorKinds = kinds
        let desktopCount = kinds.reduce(into: 0) { result, kind in
            if case .desktop(let colorIndex) = kind {
                result = max(result, colorIndex + 1)
            }
        }

        let sizeScale = CGFloat(settings.indicatorSizeScale)
        let spacingScale = CGFloat(settings.indicatorSpacingScale)
        statusItem.length = StatusItemArtwork.preferredWidth(
            for: count,
            sizeScale: sizeScale,
            spacingScale: spacingScale
        )
        guard let button = statusItem.button else { return }

        button.image = nil
        button.contentTintColor = nil

        indicatorView?.removeFromSuperview()
        let indicatorView = StatusIndicatorView(
            count: count,
            sizeScale: sizeScale,
            spacingScale: spacingScale,
            indicatorKinds: kinds,
            indicatorColors: settings.indicatorColors(for: desktopCount)
        )
        button.addSubview(indicatorView)
        NSLayoutConstraint.activate([
            indicatorView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            indicatorView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            indicatorView.topAnchor.constraint(equalTo: button.topAnchor),
            indicatorView.bottomAnchor.constraint(equalTo: button.bottomAnchor)
        ])
        self.indicatorView = indicatorView

        if let index = viewModel.activeIndex, (0..<count).contains(index) {
            renderedActiveIndex = index
            indicatorView.setActiveIndex(index, animated: false)
        } else {
            renderedActiveIndex = nil
            indicatorView.setActiveIndex(nil, animated: false)
        }
    }

    private func transitionArtwork(to indicators: [SpaceIndicatorEntry]) {
        guard !isAnimatingStructureChange else {
            needsStructureRefresh = true
            return
        }

        let newIdentifiers = indicators.map(\.id)
        guard
            let removedIndex = singleRemovedIndex(
                from: renderedIndicatorIdentifiers,
                to: newIdentifiers
            ),
            indicatorView != nil
        else {
            updateArtwork(for: indicators.count, force: true)
            return
        }

        isAnimatingStructureChange = true
        let wasFullscreen = renderedIndicatorKinds.indices.contains(removedIndex)
            && renderedIndicatorKinds[removedIndex].isFullscreen
        indicatorView?.animateRemoval(
            at: removedIndex,
            resultingCount: indicators.count,
            fullscreen: wasFullscreen
        ) { [weak self] in
            guard let self else { return }
            self.isAnimatingStructureChange = false
            self.updateArtwork(for: self.viewModel.spaceCount, force: true)
            if self.needsStructureRefresh {
                self.needsStructureRefresh = false
                self.updateArtwork(for: self.viewModel.spaceCount, force: true)
            }
        }
    }

    private func singleRemovedIndex(
        from oldIdentifiers: [Int64],
        to newIdentifiers: [Int64]
    ) -> Int? {
        guard oldIdentifiers.count == newIdentifiers.count + 1 else {
            return nil
        }
        for index in oldIdentifiers.indices {
            var candidate = oldIdentifiers
            candidate.remove(at: index)
            if candidate == newIdentifiers { return index }
        }
        return nil
    }

    private func updateActivePill(to index: Int?, animated: Bool) {
        guard !isAnimatingStructureChange else { return }
        guard
            let index,
            (0..<renderedSpaceCount).contains(index)
        else {
            renderedActiveIndex = nil
            indicatorView?.setActiveIndex(nil, animated: false)
            return
        }

        let shouldAnimate = animated
            && settings.animateIndicator
            && renderedActiveIndex != nil
            && renderedActiveIndex != index
        renderedActiveIndex = index
        indicatorView?.setActiveIndex(index, animated: shouldAnimate)
    }

    private func updateAccessibilityValue(_ index: Int?) {
        guard let index else {
            statusItem.button?.setAccessibilityValue(nil)
            return
        }
        statusItem.button?.setAccessibilityValue(
            L10n.format(
                "accessibility.workspace.position",
                index + 1,
                renderedSpaceCount
            )
        )
    }

    private func updateToolTip(_ message: String?) {
        statusItem.button?.toolTip = message ?? L10n.string("status.tooltip")
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard NSApp.currentEvent?.type == .rightMouseDown else { return }

        // NSStatusBarButton's window coordinates can be invalid in the narrow
        // gaps at the top and bottom of the menu bar. Capture stable screen
        // coordinates synchronously, before AppKit reuses the event object.
        let buttonFrame = sender.window?.convertToScreen(sender.frame) ?? .zero

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self, weak sender] in
            guard let self, let sender else { return }
            let menu = self.makeContextMenu()
            menu.popUp(
                positioning: nil,
                at: CGPoint(x: buttonFrame.minX, y: buttonFrame.minY),
                in: nil
            )
            sender.isHighlighted = false
        }
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item(L10n.string("menu.refresh"), action: #selector(refresh), symbol: "arrow.clockwise"))
        menu.addItem(settingsMenuItem())
        menu.addItem(.separator())
        menu.addItem(item(L10n.string("menu.quit"), action: #selector(quit), symbol: "power", key: "q"))
        return menu
    }

    private func settingsMenuItem() -> NSMenuItem {
        let title = L10n.string("menu.settings")
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        parent.image = NSImage(
            systemSymbolName: "gearshape",
            accessibilityDescription: title
        )

        let submenu = NSMenu(title: title)
        let launchAtLogin = item(
            L10n.string("menu.launchAtLogin"),
            action: #selector(toggleLaunchAtLogin),
            symbol: "person.crop.circle.badge.checkmark"
        )
        launchAtLogin.state = settings.launchAtLoginState
        submenu.addItem(launchAtLogin)

        let animation = item(
            L10n.string("menu.animation"),
            action: #selector(toggleAnimation),
            symbol: "sparkles"
        )
        animation.state = settings.animateIndicator ? .on : .off
        submenu.addItem(animation)
        submenu.addItem(.separator())
        submenu.addItem(indicatorColorsControlItem())
        submenu.addItem(
            item(
                L10n.string("menu.resetIndicatorColors"),
                action: #selector(resetIndicatorColors),
                symbol: "arrow.counterclockwise"
            )
        )
        submenu.addItem(.separator())
        submenu.addItem(
            sliderItem(
                title: L10n.string("menu.indicatorSize"),
                value: settings.indicatorSizeScale,
                steps: AppSettings.indicatorSizeSteps,
                action: #selector(indicatorSizeChanged(_:))
            )
        )
        submenu.addItem(
            sliderItem(
                title: L10n.string("menu.indicatorSpacing"),
                value: settings.indicatorSpacingScale,
                steps: AppSettings.indicatorSpacingSteps,
                action: #selector(indicatorSpacingChanged(_:))
            )
        )
        parent.submenu = submenu
        return parent
    }

    private func item(_ title: String, action: Selector, symbol: String, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        return item
    }

    private func sliderItem(
        title: String,
        value: Double,
        steps: [Double],
        action: Selector
    ) -> NSMenuItem {
        precondition(steps.count >= 2)
        let menuItem = NSMenuItem()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 54))

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.translatesAutoresizingMaskIntoConstraints = false

        let slider = NSSlider(
            value: value,
            minValue: steps[0],
            maxValue: steps[steps.count - 1],
            target: self,
            action: action
        )
        slider.isContinuous = true
        slider.controlSize = .small
        slider.numberOfTickMarks = steps.count
        slider.tickMarkPosition = .below
        slider.allowsTickMarkValuesOnly = true
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.setAccessibilityLabel(title)

        container.addSubview(label)
        container.addSubview(slider)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            slider.leadingAnchor.constraint(equalTo: label.leadingAnchor),
            slider.trailingAnchor.constraint(equalTo: label.trailingAnchor),
            slider.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 3)
        ])
        menuItem.view = container
        return menuItem
    }

    private func indicatorColorsControlItem() -> NSMenuItem {
        let menuItem = NSMenuItem()
        let title = L10n.string("menu.indicatorColor")
        let colorIndices = renderedDesktopColorIndices
        let desktopCount = colorIndices.count
        let colors = settings.indicatorColors(for: renderedDesktopColorSlotCount)
        let maximumButtonsPerRow = 8
        let rowCount = max(
            Int(ceil(Double(desktopCount) / Double(maximumButtonsPerRow))),
            1
        )
        let containerHeight = CGFloat(30 + rowCount * 24)
        let container = NSView(
            frame: NSRect(x: 0, y: 0, width: 280, height: containerHeight)
        )

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 6)
        ])

        var previousRow: NSStackView?
        for row in 0..<rowCount {
            let rowStart = row * maximumButtonsPerRow
            let rowEnd = min(rowStart + maximumButtonsPerRow, desktopCount)
            let stack = NSStackView()
            stack.orientation = .horizontal
            stack.alignment = .centerY
            stack.spacing = 4
            stack.translatesAutoresizingMaskIntoConstraints = false

            for position in rowStart..<rowEnd {
                let colorIndex = colorIndices[position]
                let itemTitle = L10n.format("menu.indicatorNumber", position + 1)
                let button = NSButton()
                button.isBordered = false
                button.image = colorSwatch(colors[colorIndex], size: 18)
                button.imageScaling = .scaleNone
                button.target = self
                button.action = #selector(chooseIndicatorColor(_:))
                button.tag = colorIndex
                button.toolTip = itemTitle
                button.setAccessibilityLabel(itemTitle)
                button.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    button.widthAnchor.constraint(equalToConstant: 22),
                    button.heightAnchor.constraint(equalToConstant: 22)
                ])
                stack.addArrangedSubview(button)
            }

            container.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: label.leadingAnchor),
                stack.trailingAnchor.constraint(lessThanOrEqualTo: label.trailingAnchor),
                stack.topAnchor.constraint(
                    equalTo: previousRow?.bottomAnchor ?? label.bottomAnchor,
                    constant: 3
                )
            ])
            previousRow = stack
        }

        menuItem.view = container
        return menuItem
    }

    private func colorSwatch(_ color: NSColor, size: CGFloat = 16) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let swatchRect = rect.insetBy(dx: 2, dy: 2)
            let path = NSBezierPath(ovalIn: swatchRect)
            color.setFill()
            path.fill()
            NSColor.separatorColor.setStroke()
            path.lineWidth = 1
            path.stroke()
            return true
        }
    }

    private func presentColorPanel(for index: Int) {
        guard renderedDesktopColorIndices.contains(index) else { return }
        selectedIndicatorColorIndex = index

        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.color = settings.indicatorColors(for: renderedDesktopColorSlotCount)[index]
        panel.setTarget(self)
        panel.setAction(#selector(indicatorColorChanged(_:)))
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private var renderedDesktopCount: Int {
        renderedDesktopColorIndices.count
    }

    private var renderedDesktopColorIndices: [Int] {
        renderedIndicatorKinds.compactMap { kind in
            guard case .desktop(let colorIndex) = kind else { return nil }
            return colorIndex
        }
    }

    private var renderedDesktopColorSlotCount: Int {
        (renderedDesktopColorIndices.max() ?? 0) + 1
    }

    @objc private func chooseIndicatorColor(_ sender: NSButton) {
        let index = sender.tag
        sender.enclosingMenuItem?.menu?.cancelTracking()
        DispatchQueue.main.async { [weak self] in
            self?.presentColorPanel(for: index)
        }
    }

    @objc private func resetIndicatorColors() {
        settings.resetIndicatorColors()
        selectedIndicatorColorIndex = nil
        NSColorPanel.shared.orderOut(nil)
    }

    @objc private func refresh() {
        Task { await viewModel.refresh() }
    }

    @objc private func toggleLaunchAtLogin() {
        settings.toggleLaunchAtLogin()
    }

    @objc private func toggleAnimation() {
        settings.toggleAnimation()
    }

    @objc private func indicatorSizeChanged(_ sender: NSSlider) {
        settings.setIndicatorSizeScale(sender.doubleValue)
    }

    @objc private func indicatorSpacingChanged(_ sender: NSSlider) {
        settings.setIndicatorSpacingScale(sender.doubleValue)
    }

    @objc private func indicatorColorChanged(_ sender: NSColorPanel) {
        guard let index = selectedIndicatorColorIndex else { return }
        settings.setIndicatorColor(sender.color, at: index)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
