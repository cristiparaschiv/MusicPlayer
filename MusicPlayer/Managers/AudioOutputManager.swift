import Foundation
import CoreAudio
import AVFoundation
import Combine

/// Manages audio output device selection, sample rate switching, hog mode, and monitoring
@MainActor
class AudioOutputManager: ObservableObject {
    static let shared = AudioOutputManager()

    @Published var availableDevices: [AudioDevice] = []
    @Published var currentDevice: AudioDevice?
    @Published var currentSampleRate: Double = 0
    @Published var isHogModeEnabled: Bool = false
    @Published var isSampleRateSwitchingEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isSampleRateSwitchingEnabled, forKey: "sampleRateSwitchingEnabled")
        }
    }

    private var hoggedDeviceID: AudioDeviceID?

    private init() {
        let devices = AudioOutputManager.fetchAvailableDevices()
        let current = AudioOutputManager.fetchCurrentDevice()
        self.availableDevices = devices
        self.currentDevice = current
        self.isSampleRateSwitchingEnabled = UserDefaults.standard.bool(forKey: "sampleRateSwitchingEnabled")
        if let current = current {
            self.currentSampleRate = AudioOutputManager.getDeviceSampleRate(current.id)
        }
        setupDeviceNotifications()
    }

    // MARK: - Public Methods

    /// Set the default audio output device
    func setOutputDevice(_ device: AudioDevice) -> Bool {
        // Release hog mode on old device first
        if isHogModeEnabled {
            releaseHogMode()
        }

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
            self.currentDevice = device
            self.currentSampleRate = AudioOutputManager.getDeviceSampleRate(device.id)
            return true
        }

        return false
    }

    /// Refresh the list of available devices
    func refreshDevices() {
        self.availableDevices = AudioOutputManager.fetchAvailableDevices()
        self.currentDevice = AudioOutputManager.fetchCurrentDevice()
        if let current = currentDevice {
            self.currentSampleRate = AudioOutputManager.getDeviceSampleRate(current.id)
        }
    }

    // MARK: - Sample Rate Switching

    /// Switch the output device sample rate to match the track's sample rate
    func matchSampleRate(trackSampleRate: Int?) {
        guard isSampleRateSwitchingEnabled,
              let trackRate = trackSampleRate, trackRate > 0,
              let device = currentDevice else { return }

        let targetRate = Double(trackRate)
        let currentRate = AudioOutputManager.getDeviceSampleRate(device.id)

        // Don't switch if already matching
        guard abs(currentRate - targetRate) > 1.0 else { return }

        // Check if the device supports this sample rate
        let supportedRates = AudioOutputManager.getSupportedSampleRates(device.id)
        guard supportedRates.contains(where: { $0.mMinimum <= targetRate && targetRate <= $0.mMaximum }) else {
            // Device does not support this sample rate
            return
        }

        // Set the sample rate
        if AudioOutputManager.setDeviceSampleRate(device.id, sampleRate: targetRate) {
            self.currentSampleRate = targetRate
        }
    }

    // MARK: - Hog Mode

    /// Take exclusive access (hog mode) of the current output device
    func enableHogMode() {
        guard let device = currentDevice else { return }

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyHogMode,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var pid = ProcessInfo.processInfo.processIdentifier
        let dataSize = UInt32(MemoryLayout<pid_t>.size)

        let status = AudioObjectSetPropertyData(
            device.id,
            &propertyAddress,
            0,
            nil,
            dataSize,
            &pid
        )

        if status == kAudioHardwareNoError {
            hoggedDeviceID = device.id
            isHogModeEnabled = true
        } else {
        }
    }

    /// Release exclusive access of the current output device
    func releaseHogMode() {
        guard let deviceID = hoggedDeviceID else { return }

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyHogMode,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var pid: pid_t = -1
        let dataSize = UInt32(MemoryLayout<pid_t>.size)

        let status = AudioObjectSetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            dataSize,
            &pid
        )

        if status == kAudioHardwareNoError {
            hoggedDeviceID = nil
            isHogModeEnabled = false
        } else {
        }
    }

    /// Toggle hog mode
    func toggleHogMode() {
        if isHogModeEnabled {
            releaseHogMode()
        } else {
            enableHogMode()
        }
        UserDefaults.standard.set(isHogModeEnabled, forKey: "hogModeEnabled")
    }

    // MARK: - Static (nonisolated) device query methods

    nonisolated static func fetchAvailableDevices() -> [AudioDevice] {
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

    nonisolated static func fetchCurrentDevice() -> AudioDevice? {
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

    // MARK: - Sample Rate Helpers

    nonisolated static func getDeviceSampleRate(_ deviceID: AudioDeviceID) -> Double {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var sampleRate: Float64 = 0
        var dataSize = UInt32(MemoryLayout<Float64>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &sampleRate
        )

        return status == kAudioHardwareNoError ? sampleRate : 0
    }

    nonisolated static func getSupportedSampleRates(_ deviceID: AudioDeviceID) -> [AudioValueRange] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyAvailableNominalSampleRates,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard status == kAudioHardwareNoError, dataSize > 0 else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioValueRange>.size
        var ranges = [AudioValueRange](repeating: AudioValueRange(), count: count)

        let getStatus = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &ranges
        )

        return getStatus == kAudioHardwareNoError ? ranges : []
    }

    nonisolated static func setDeviceSampleRate(_ deviceID: AudioDeviceID, sampleRate: Double) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var rate = Float64(sampleRate)
        let dataSize = UInt32(MemoryLayout<Float64>.size)

        let status = AudioObjectSetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            dataSize,
            &rate
        )

        return status == kAudioHardwareNoError
    }

    // MARK: - Formatting

    nonisolated static func formatSampleRate(_ rate: Double) -> String {
        let khz = rate / 1000.0
        if khz.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(khz)) kHz"
        }
        return String(format: "%.1f kHz", khz)
    }

    // MARK: - Transport Type Helper

    nonisolated static func getTransportType(_ deviceID: AudioDeviceID) -> UInt32 {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var transportType: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &transportType
        )

        return status == kAudioHardwareNoError ? transportType : 0
    }

    // MARK: - Private Static Helpers

    nonisolated private static func isOutputDevice(_ deviceID: AudioDeviceID) -> Bool {
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

        guard status == kAudioHardwareNoError, dataSize > 0 else { return false }

        let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { bufferListPointer.deallocate() }

        let getDataStatus = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            bufferListPointer
        )

        guard getDataStatus == kAudioHardwareNoError else { return false }

        return bufferListPointer.pointee.mNumberBuffers > 0
    }

    nonisolated private static func getDeviceInfo(_ deviceID: AudioDeviceID) -> AudioDevice? {
        guard let name = getDeviceName(deviceID) else { return nil }
        let transportType = getTransportType(deviceID)
        let isAirPlay = transportType == kAudioDeviceTransportTypeAirPlay
        return AudioDevice(id: deviceID, name: name, isAirPlay: isAirPlay)
    }

    nonisolated private static func getDeviceName(_ deviceID: AudioDeviceID) -> String? {
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

    // MARK: - Device Change Notifications

    private nonisolated func setupDeviceNotifications() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            { (_, _, _, clientData) -> OSStatus in
                guard let clientData = clientData else { return kAudioHardwareNoError }
                let manager = Unmanaged<AudioOutputManager>.fromOpaque(clientData).takeUnretainedValue()
                DispatchQueue.main.async {
                    manager.refreshDevices()
                }
                return kAudioHardwareNoError
            },
            selfPtr
        )
    }
}

// MARK: - Supporting Types

struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
    let isAirPlay: Bool

    init(id: AudioDeviceID, name: String, isAirPlay: Bool = false) {
        self.id = id
        self.name = name
        self.isAirPlay = isAirPlay
    }

    var displayName: String {
        if isAirPlay {
            return "\(name) (AirPlay)"
        }
        return name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: AudioDevice, rhs: AudioDevice) -> Bool {
        return lhs.id == rhs.id
    }
}
