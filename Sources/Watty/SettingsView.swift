import AppKit
import SwiftUI
import WattyCore

struct SettingsView: View {
    static let width: CGFloat = 480

    @EnvironmentObject var model: BatteryModel
    @EnvironmentObject var launchAtLogin: LaunchAtLoginController
    @EnvironmentObject var notifications: NotificationService

    var body: some View {
        Form {
            MenuBarSettingsSection()
            if model.hasBattery {
                NotificationSettingsSection()
            }
            LaunchAtLoginSection()
        }
        .formStyle(.grouped)
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear(perform: refreshExternalState)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshExternalState()
        }
    }

    private func refreshExternalState() {
        launchAtLogin.refresh()
        Task { await notifications.refreshPermission() }
    }
}

struct MenuBarSettingsSection: View {
    @EnvironmentObject var model: BatteryModel
    @AppStorage(PreferenceKey.menuBarDisplay) private var display: MenuBarDisplay = .percentage

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Picker("Show in menu bar", selection: $display) {
                    ForEach(MenuBarDisplay.options(hasBattery: model.hasBattery)) { option in
                        Text(title(for: option)).tag(option)
                    }
                }
                Text(explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LabeledContent("Preview") {
                MenuBarLabel(model: model, display: display)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                    .accessibilityHidden(true)
            }
        } header: {
            Text("Menu bar")
        }
    }

    private func title(for option: MenuBarDisplay) -> LocalizedStringKey {
        switch option {
        case .percentage: return model.hasBattery ? "Percentage" : "CPU usage"
        case .timeRemaining: return "Time remaining"
        case .power: return "Power (W)"
        case .iconOnly: return "Icon only"
        }
    }

    private var explanation: LocalizedStringKey {
        guard model.hasBattery else {
            return display == .iconOnly
                ? "Only the icon is shown. This Mac has no battery."
                : "This Mac has no battery, so the menu bar shows CPU usage."
        }
        switch display {
        case .percentage: return "The battery level."
        case .timeRemaining: return "Time left on battery, or time to full while charging."
        case .power: return "Battery draw in watts on battery, adapter input while plugged in."
        case .iconOnly: return "Only the battery icon."
        }
    }
}

struct NotificationSettingsSection: View {
    @EnvironmentObject var notifications: NotificationService

    @AppStorage(PreferenceKey.notifyLowBattery) private var lowBatteryEnabled = false
    @AppStorage(PreferenceKey.lowBatteryLevel) private var lowBatteryLevel = PreferenceDefault.lowBatteryLevel
    @AppStorage(PreferenceKey.notifyChargeLimit) private var chargeLimitEnabled = false
    @AppStorage(PreferenceKey.chargeLimitLevel) private var chargeLimitLevel = PreferenceDefault.chargeLimitLevel
    @AppStorage(PreferenceKey.notifyFullyCharged) private var fullyChargedEnabled = false

    var body: some View {
        Section {
            alertRow(
                "Low battery",
                detail: "Alert when the battery drops to this level on battery power.",
                isOn: $lowBatteryEnabled,
                level: $lowBatteryLevel,
                levels: PreferenceDefault.lowBatteryLevels
            )
            alertRow(
                "Charge limit reminder",
                detail: "Remind me to unplug when charging reaches this level, to go easy on the battery.",
                isOn: $chargeLimitEnabled,
                level: $chargeLimitLevel,
                levels: PreferenceDefault.chargeLimitLevels
            )
            VStack(alignment: .leading, spacing: 2) {
                Toggle("Fully charged", isOn: requestingPermission($fullyChargedEnabled))
                Text("Alert when the battery is full on the charger.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            permissionNotice
        } header: {
            Text("Notifications")
        }
    }

    private func alertRow(
        _ title: LocalizedStringKey,
        detail: LocalizedStringKey,
        isOn: Binding<Bool>,
        level: Binding<Int>,
        levels: ClosedRange<Int>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Toggle(title, isOn: requestingPermission(isOn))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if isOn.wrappedValue {
                LabeledContent("Alert level") {
                    HStack(spacing: 6) {
                        Text(ValueFormat.percent(level.wrappedValue))
                            .monospacedDigit()
                        Stepper("Alert level", value: level, in: levels)
                            .labelsHidden()
                    }
                }
                .padding(.leading, 20)
            }
        }
    }

    private func requestingPermission(_ isOn: Binding<Bool>) -> Binding<Bool> {
        Binding(
            get: { isOn.wrappedValue },
            set: { newValue in
                isOn.wrappedValue = newValue
                if newValue {
                    Task { await notifications.requestPermissionIfNeeded() }
                }
            }
        )
    }

    @ViewBuilder
    private var permissionNotice: some View {
        switch notifications.permission {
        case .denied:
            VStack(alignment: .leading, spacing: 6) {
                Label("Notifications are turned off for Watty in System Settings.", systemImage: "bell.slash")
                    .foregroundStyle(.orange)
                Button("Open Notification Settings…") {
                    notifications.openSystemSettings()
                }
            }
        case .unsupported:
            Label("Notifications need Watty to run as an app.", systemImage: "info.circle")
                .foregroundStyle(.secondary)
        case .notDetermined, .allowed:
            EmptyView()
        }

        if let message = notifications.errorMessage {
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
    }
}

struct LaunchAtLoginSection: View {
    @EnvironmentObject var launchAtLogin: LaunchAtLoginController

    var body: some View {
        Section {
            switch launchAtLogin.mode {
            case .system:
                systemControls
            case .homebrew:
                homebrewNotice
            case .unavailable:
                Label("Launch at login needs Watty to run as an app.", systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Startup")
        }
    }

    @ViewBuilder
    private var systemControls: some View {
        Toggle("Launch at login", isOn: Binding(
            get: { launchAtLogin.isEnabled },
            set: { launchAtLogin.setEnabled($0) }
        ))

        if launchAtLogin.needsApproval {
            VStack(alignment: .leading, spacing: 6) {
                Label("Approve Watty in System Settings > General > Login Items.", systemImage: "hand.raised")
                    .foregroundStyle(.orange)
                Button("Open Login Items…") {
                    launchAtLogin.openLoginItemsSettings()
                }
            }
        }

        if let message = launchAtLogin.errorMessage {
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
    }

    private var homebrewNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Watty is managed by Homebrew.", systemImage: "shippingbox")
            Text("The app's path changes with every upgrade, so start it at login with Homebrew instead:")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Text(LaunchAtLoginController.homebrewStartCommand)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(LaunchAtLoginController.homebrewStartCommand, forType: .string)
                }
                .controlSize(.small)
            }
        }
    }
}
