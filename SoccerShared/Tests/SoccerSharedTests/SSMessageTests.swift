import Testing
import Foundation
@testable import SoccerShared

struct SSMessageTests {

    @Test func kickRoundTrips() throws {
        let kick = KickEvent(seq: 7, tMono: 123, kind: .shoot, power: 0.8, aim: -0.3, loft: 0.2)
        let data = try SSMessage.kick(kick).encoded()
        let decoded = try SSMessage.decode(data)
        #expect(decoded == .kick(kick))
    }

    @Test func helloRoundTrips() throws {
        let hello = HelloPayload(role: .controller, protoVersion: SSProtocol.version, tMono: 1)
        let data = try SSMessage.hello(hello).encoded()
        #expect(try SSMessage.decode(data) == .hello(hello))
    }

    @Test func goalRoundTrips() throws {
        let goal = GoalEvent(outcome: .goal, intensity: 1.0, teamScore: 1, opponentScore: 0)
        let data = try SSMessage.goal(goal).encoded()
        #expect(try SSMessage.decode(data) == .goal(goal))
    }
}
