import CloudKit
import Foundation

/// Keeps one timer record in the person's private iCloud database.
///
/// The record lives in its own zone so a database subscription can wake the other
/// devices with a silent push whenever it changes.
public final class CloudSync: Sendable {
    /// The container named in the target's Info.plist under `SpiderCloudContainer`.
    public static let shared: CloudSync? = (Bundle.main.object(forInfoDictionaryKey: "SpiderCloudContainer") as? String)
        .map(CloudSync.init(containerID:))

    static let zoneID = CKRecordZone.ID(zoneName: "SpiderTimer", ownerName: CKCurrentUserDefaultName)
    static let recordID = CKRecord.ID(recordName: "current", zoneID: zoneID)
    static let recordType = "Timer"
    static let subscriptionID = "timer-changes"

    private let containerID: String

    public init(containerID: String) {
        self.containerID = containerID
    }

    private var database: CKDatabase {
        CKContainer(identifier: containerID).privateCloudDatabase
    }

    /// Creates the zone and the change subscription. Safe to call on every launch.
    public func prepare() async throws {
        let database = database
        _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: Self.zoneID)], deleting: [])

        let subscription = CKDatabaseSubscription(subscriptionID: Self.subscriptionID)
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        _ = try await database.modifySubscriptions(saving: [subscription], deleting: [])
    }

    /// The timer on the server, or nil if no device has saved one yet.
    public func fetch() async throws -> SyncSnapshot? {
        guard let record = try await fetchRecord() else { return nil }
        return Self.snapshot(from: record)
    }

    /// Saves `snapshot` unless the server already has something newer.
    /// Returns what the server holds afterwards, so the caller can adopt it if it lost.
    @discardableResult
    public func push(_ snapshot: SyncSnapshot) async throws -> SyncSnapshot {
        for attempt in 1...3 {
            let record = try await fetchRecord() ?? CKRecord(recordType: Self.recordType, recordID: Self.recordID)
            if let server = Self.snapshot(from: record),
               SyncSnapshot.decide(local: snapshot, remote: server) != .pushLocal {
                return server
            }
            record["payload"] = try JSONEncoder().encode(snapshot) as NSData
            record["changedAt"] = snapshot.changedAt as NSDate

            do {
                let (saved, _) = try await database.modifyRecords(
                    saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: true
                )
                if case .failure(let error) = saved[Self.recordID] { throw error }
                return snapshot
            } catch let error as CKError where error.code == .serverRecordChanged && attempt < 3 {
                // Another device saved in between: look again.
                continue
            }
        }
        return snapshot
    }

    private func fetchRecord() async throws -> CKRecord? {
        do {
            return try await database.record(for: Self.recordID)
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            return nil
        }
    }

    private static func snapshot(from record: CKRecord) -> SyncSnapshot? {
        guard let data = record["payload"] as? Data else { return nil }
        return try? JSONDecoder().decode(SyncSnapshot.self, from: data)
    }
}
