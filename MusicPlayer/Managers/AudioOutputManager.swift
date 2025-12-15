import Foundation
import CoreAudio
import AVFoundation
import Combine

/// Manages audio output device selection and monitoring
class AudioOutputManager: ObservableObject {
    static let shared = AudioOutputManager()

    @Published var availableDevices: [AudioDevice] = []
    @Published var currentDevice: AudioDevice?

    private init() {
        loadDevices()
        setupDeviceNotifications()
    }

    // MARK: - Public Methods

    /// Get list of all available audio output devices
    func getAvailableDevices() -> [AudioDevice] {
        var devices: [AudioDevice] = []

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard status == kAudioHardwareNoError else { return devices }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        let getDevicesStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )

        guard getDevicesStatus == kAudioHardwareNoError else { return devices }

        for deviceID in deviceIDs {
            if isOutputDevice(deviceID), let device = getDeviceInfo(deviceID) {
                devices.append(device)
            }
        }

        return devices
    }

    /// Get the current default output device
    func getCurrentDevice() -> AudioDevice? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        )

        guard status == kAudioHardwareNoError else { return nil }

        return getDeviceInfo(deviceID)
    }

    /// Set the default audio output device
    func setOutputDevice(_ device: AudioDevice) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID = device.id
        let dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            dataSize,
            &deviceID
        )

        if status == kAudioHardwareNoError {
            DispatchQueue.main.async {
                self.currentDevice = device
            }
            return true
        }

        return false
    }

    /// Refresh the list of available devices
    func refreshDevices() {
        loadDevices()
    }

    // MARK: - Private Methods

    private func loadDevices() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let devices = self.getAvailableDevices()
            let current = self.getCurrentDevice()

            DispatchQueue.main.async {
                self.availableDevices = devices
                self.currentDevice = current
            }
        }
    }

    private func isOutputDevice(_ deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: 0
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard status == kAudioHardwareNoError else { return false }

        let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { bufferList.deallocate() }

        let getDataStatus = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            bufferList
        )

        guard getDataStatus == kAudioHardwareNoError else { return false }

        return bufferList.pointee.mNumberBuffers > 0
    }

    private func getDeviceInfo(_ deviceID: AudioDeviceID) -> AudioDevice? {
        guard let name = getDeviceName(deviceID) else { return nil }

        return AudioDevice(id: deviceID, name: name)
    }

    private func getDeviceName(_ deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize = UInt32(MemoryLayout<CFString>.size)
        var deviceName: CFString = "" as CFString

        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceName
        )

        guard status == kAudioHardwareNoError else { return nil }

        return deviceName as String
    }

    private func setupDeviceNotifications() {
        // Listen for device configuration changes
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            { (objectID, numberAddresses, addresses, clientData) -> OSStatus in
                guard let manager = clientData?.assumingMemoryBound(to: AudioOutputManager.self).pointee else {
                    return kAudioHardwareNoError
                }

                manager.loadDevices()
                return kAudioHardwareNoError
            },
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
    }
}

// MARK: - Supporting Types

struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: AudioDevice, rhs: AudioDevice) -> Bool {
        return lhs.id == rhs.id
    }
}
