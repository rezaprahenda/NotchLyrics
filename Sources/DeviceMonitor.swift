import AppKit
import Combine
import CoreAudio
import IOKit.ps

/// Peek untuk charger / baterai dan headphone Bluetooth. Tidak butuh izin tambahan:
/// baterai dari IOKit, headphone dari perangkat output audio CoreAudio.
/// (Persentase baterai AirPods tidak tersedia lewat API publik.)
final class DeviceModule: ObservableObject {
    @Published var batteryAlerts: Bool = Defaults.bool("device.battery", true) {
        didSet { UserDefaults.standard.set(batteryAlerts, forKey: "device.battery") }
    }
    @Published var audioAlerts: Bool = Defaults.bool("device.audio", true) {
        didSet { UserDefaults.standard.set(audioAlerts, forKey: "device.audio") }
    }

    var onPeek: ((PeekEvent) -> Void)?

    private var powerSource: CFRunLoopSource?
    private var lastExternal: Bool?
    private var lowAlerted: Set<Int> = []
    private var lastOutput = AudioDeviceID(0)

    struct Power {
        let external: Bool
        let charging: Bool
        let percent: Int
        let minutesToFull: Int?
    }

    func start() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let me = Unmanaged<DeviceModule>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async { me.powerChanged() }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            powerSource = source
        }
        lastExternal = Self.readPower()?.external

        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main) { [weak self] _, _ in
            self?.outputChanged()
        }
        lastOutput = Self.defaultOutput()
    }

    // MARK: - Baterai

    private func powerChanged() {
        guard let p = Self.readPower() else { return }
        defer { lastExternal = p.external }
        guard batteryAlerts else { return }

        if let last = lastExternal, last != p.external {
            if p.external {
                let subtitle = p.minutesToFull.map { m in
                    let h = m / 60, mm = m % 60
                    return h > 0 ? L("Penuh sekitar \(h) j \(mm) m", "Full in about \(h)h \(mm)m")
                                 : L("Penuh sekitar \(mm) menit", "Full in about \(mm) min")
                } ?? ""
                post(L("Mengisi daya · \(p.percent)%", "Charging · \(p.percent)%"), subtitle, "battery.100percent.bolt")
            } else {
                post(L("Charger dicabut · \(p.percent)%", "Unplugged · \(p.percent)%"), "", symbol(for: p.percent))
            }
        }

        if p.external {
            lowAlerted = []
        } else {
            for threshold in [5, 10] where p.percent <= threshold && !lowAlerted.contains(threshold) {
                lowAlerted.formUnion([5, 10].filter { $0 >= threshold })
                post(L("Baterai lemah · \(p.percent)%", "Battery low · \(p.percent)%"),
                     L("Colokkan charger", "Plug in the charger"), "battery.25percent")
                break
            }
        }
    }

    private func symbol(for percent: Int) -> String {
        switch percent {
        case ..<20: return "battery.25percent"
        case ..<60: return "battery.50percent"
        case ..<90: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    static func readPower() -> Power? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let current = d[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
            let ttf = d[kIOPSTimeToFullChargeKey] as? Int ?? -1
            return Power(external: (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue,
                         charging: d[kIOPSIsChargingKey] as? Bool ?? false,
                         percent: max > 0 ? current * 100 / max : current,
                         minutesToFull: ttf > 0 ? ttf : nil)
        }
        return nil
    }

    // MARK: - Headphone

    private func outputChanged() {
        let device = Self.defaultOutput()
        defer { lastOutput = device }
        guard audioAlerts, device != 0, device != lastOutput, Self.isBluetooth(device) else { return }
        let name = Self.name(of: device) ?? L("Headphone", "Headphones")
        let symbol = name.lowercased().contains("airpods") ? "airpodspro" : "headphones"
        post(L("\(name) tersambung", "\(name) connected"), "", symbol)
    }

    private static func defaultOutput() -> AudioDeviceID {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return device
    }

    private static func isBluetooth(_ device: AudioDeviceID) -> Bool {
        var transport = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport) == noErr else { return false }
        return transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    private static func name(of device: AudioDeviceID) -> String? {
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr,
              let value = name?.takeRetainedValue() else { return nil }
        return value as String
    }

    private func post(_ title: String, _ subtitle: String, _ symbol: String) {
        onPeek?(PeekEvent(kind: .device, id: title, createdAt: Date(), title: title, subtitle: subtitle, symbol: symbol))
    }
}
