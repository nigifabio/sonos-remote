import Foundation

/// The one method of `URLSession` `SOAPClient` actually needs — extracted so
/// tests can substitute a fake that records requests and returns canned XML,
/// instead of every `SonosController` call needing real Sonos hardware to
/// exercise. Every call site defaults to `URLSession.shared`, so this is
/// purely additive: nothing about production behavior changes.
protocol SOAPTransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: SOAPTransport {}
