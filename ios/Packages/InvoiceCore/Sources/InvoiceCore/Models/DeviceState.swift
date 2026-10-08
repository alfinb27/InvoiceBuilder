/// This device's local row (`device_state`): never synced, never backed up (`spec/setup.md` §2).
public struct DeviceState: Codable, Hashable, Sendable, Identifiable {
    /// This device's id: the `ownerDeviceId` of the numbering series it creates.
    public var id: String
    public var deviceName: String
    public var freeCounterMirror: Int64
    public var preferences: DevicePreferences
    public var createdAt: Int64
    public var updatedAt: Int64

    public init(id: String, deviceName: String, freeCounterMirror: Int64 = 0,
                preferences: DevicePreferences = DevicePreferences(), createdAt: Int64 = 0, updatedAt: Int64 = 0) {
        self.id = id
        self.deviceName = deviceName
        self.freeCounterMirror = freeCounterMirror
        self.preferences = preferences
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct DevicePreferences: Codable, Hashable, Sendable {
    public var activeBusinessId: String?
    /// iCloud sync on this device (`spec/sync.md` §2); nil means on, where the build supports it.
    public var syncEnabled: Bool?

    public init(activeBusinessId: String? = nil, syncEnabled: Bool? = nil) {
        self.activeBusinessId = activeBusinessId
        self.syncEnabled = syncEnabled
    }

    public var isSyncEnabled: Bool { syncEnabled ?? true }
}
