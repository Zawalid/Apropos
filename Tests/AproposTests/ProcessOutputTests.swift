import Foundation
import Testing

@testable import Apropos

struct ProcessOutputTests {
    /// A chunk read from the pipe but not yet stored used to be lost when the process exited at that moment.
    @Test func everyByteComesBackWhenTheProcessExitsRightAway() async throws {
        let input = Data((0..<40_000).map { UInt8($0 % 251) })
        try await withThrowingTaskGroup(of: Bool.self) { group in
            for _ in 0..<40 {
                group.addTask {
                    let output = try await ProcessRunner.run(
                        ProcessRequest(executable: "/bin/cat", standardInput: input))
                    return output.standardOutput == input
                }
            }
            for try await same in group { #expect(same) }
        }
    }
}
