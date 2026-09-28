#if GROUPS
import CloudKit
import XCTest
@testable import Niyat

final class GroupCloudTests: XCTestCase {
    func testAtomicFailureDoesNotHideRootCause() {
        let schema = CKError(.serverRejectedRequest, userInfo: [NSLocalizedDescriptionKey: "Cannot create record type Group in production schema"])
        let atomic = CKError(.batchRequestFailed)
        for errors: [Error] in [[atomic, schema], [schema, atomic]] {
            let cause = GroupCloudErrors.rootCause(in: errors) as? CKError
            XCTAssertEqual(cause?.code, .serverRejectedRequest)
            XCTAssertTrue(GroupCloudErrors.message(for: cause!).contains("setup update"))
        }
    }

    func testNestedPartialFailuresAreUnwrapped() {
        let root = CKError(.networkFailure)
        let partial = CKError(.partialFailure, userInfo: [CKPartialErrorsByItemIDKey: [
            CKRecord.ID(recordName: "group"): root,
            CKRecord.ID(recordName: "member"): CKError(.batchRequestFailed)
        ]])
        XCTAssertEqual((GroupCloudErrors.rootCause(in: [partial]) as? CKError)?.code, .networkFailure)
        XCTAssertEqual(GroupCloudErrors.message(for: partial), "Check your internet connection, then try again.")
    }

    func testPerRecordFailureIsCheckedEvenWhenOperationSucceeds() {
        let group = CKRecord.ID(recordName: "group")
        let member = CKRecord.ID(recordName: "member")
        let results: [CKRecord.ID: Result<CKRecord, Error>] = [
            group: .failure(CKError(.permissionFailure)),
            member: .failure(CKError(.batchRequestFailed))
        ]
        XCTAssertThrowsError(try GroupCloudErrors.check(results)) { error in
            XCTAssertEqual((error as? CKError)?.code, .permissionFailure)
        }
        XCTAssertNoThrow(try GroupCloudErrors.check([:]))
    }

    func testRawRecordIdentifiersAreNotShown() {
        let error = CKError(.batchRequestFailed, userInfo: [NSLocalizedDescriptionKey: "Atomic failure CKRecordID member-private-user-id"])
        XCTAssertFalse(GroupCloudErrors.message(for: error).contains("private-user-id"))
    }
}
#endif
