import SwiftUI
import AppKit
import CoreAudio
import Combine

/// Perangkat output audio sistem (speaker bawaan, AirPods, monitor HDMI, AirPlay…).
struct AudioOutputDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
    let transport: UInt32

    /// Ikon SF Symbol yang mewakili jenis perangkat.
    var symbol: String {
        let lower = name.lowercased()
        if lower.contains("airpods max") { return "airpodsmax" }
        if lower.contains("airpods pro") { return "airpodspro" }
        if lower.contains("airpods") { return "airpods" }
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: return "laptopcomputer"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "headphones"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return "tv"
        case kAudioDeviceTransportTypeAirPlay: return "airplayaudio"
        case kAudioDeviceTransportTypeUSB: return "hifispeaker"
        default: return "speaker.wave.2"
        }
    }
}

/// Membaca & mengganti output audio default sistem lewat CoreAudio (berlaku untuk semua app).
enum AudioOutputs {
    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func all() -> [AudioOutputDevice] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr,
              size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr
        else { return [] }
        return ids.compactMap { id in
            guard hasOutput(id), let name = name(of: id) else { return nil }
            return AudioOutputDevice(id: id, name: name, transport: transport(of: id))
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func defaultID() -> AudioDeviceID? {
        var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr,
              id != 0 else { return nil }
        return id
    }

    static func current() -> AudioOutputDevice? {
        guard let id = defaultID() else { return nil }
        return AudioOutputDevice(id: id, name: name(of: id) ?? "", transport: transport(of: id))
    }

    @discardableResult
    static func setDefault(_ id: AudioDeviceID) -> Bool {
        // Sama seperti memilih di Control Center: hanya output utama; bunyi sistem mengikuti pengaturan macOS.
        var deviceID = id
        var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, size, &deviceID) == noErr
    }

    private static func hasOutput(_ id: AudioDeviceID) -> Bool {
        var addr = address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr && size > 0
    }

    private static func name(of id: AudioDeviceID) -> String? {
        var addr = address(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &name) == noErr,
              let value = name?.takeRetainedValue() else { return nil }
        return value as String
    }

    private static func transport(of id: AudioDeviceID) -> UInt32 {
        var addr = address(kAudioDevicePropertyTransportType)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        _ = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value)
        return value
    }
}

/// Tombol kecil di halaman Musik: ikon perangkat yang sedang dipakai, klik untuk memilih output lain.
struct AudioOutputButton: View {
    @State private var current = AudioOutputs.current()
    @State private var hover = false
    private let refresh = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        Button(action: showMenu) {
            Image(systemName: current?.symbol ?? "speaker.wave.2")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(hover ? 0.95 : 0.65))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.white.opacity(hover ? 0.12 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .onReceive(refresh) { _ in
            let now = AudioOutputs.current()
            if now != current { current = now }
        }
        .help(L("Output audio: \(current?.name ?? "-")", "Audio output: \(current?.name ?? "-")"))
        .accessibilityLabel(L("Pilih output audio", "Choose audio output"))
    }

    private func showMenu() {
        let menu = NSMenu()
        let header = NSMenuItem(title: L("Putar lewat", "Play through"), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        let selected = AudioOutputs.defaultID()
        for device in AudioOutputs.all() {
            let item = NSMenuItem(title: device.name, action: #selector(AudioOutputMenuTarget.pick(_:)), keyEquivalent: "")
            item.target = AudioOutputMenuTarget.shared
            item.representedObject = NSNumber(value: device.id)
            item.image = NSImage(systemSymbolName: device.symbol, accessibilityDescription: nil)
            item.state = device.id == selected ? .on : .off
            menu.addItem(item)
        }
        AudioOutputMenuTarget.shared.onPick = { current = AudioOutputs.current() }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

/// Target Objective-C untuk item NSMenu.
final class AudioOutputMenuTarget: NSObject {
    static let shared = AudioOutputMenuTarget()
    var onPick: (() -> Void)?

    @objc func pick(_ sender: NSMenuItem) {
        guard let number = sender.representedObject as? NSNumber else { return }
        AudioOutputs.setDefault(AudioDeviceID(number.uint32Value))
        onPick?()
    }
}
