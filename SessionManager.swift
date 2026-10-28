import Foundation
import MultipeerConnectivity
import Combine

#if os(iOS)
import UIKit
#endif

class SessionManager: NSObject, ObservableObject {

    private let serviceType = "t9system"

    private let peerID: MCPeerID = {
        #if os(iOS)
        return MCPeerID(displayName: UIDevice.current.name)
        #else
        return MCPeerID(displayName: Host.current().localizedName ?? "Mac")
        #endif
    }()

    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    @Published var connected = false
    @Published var receivedMessage = ""

    override init() {
        super.init()
        session = MCSession(
            peer: peerID,
            securityIdentity: nil,
            encryptionPreference: .required
        )
        session.delegate = self

        #if os(macOS)
        startAdvertising()
        #else
        startBrowsing()
        #endif
    }

    private func startAdvertising() {
        advertiser = MCNearbyServiceAdvertiser(
            peer: peerID,
            discoveryInfo: nil,
            serviceType: serviceType
        )
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
        print("💻 Mac advertising as: \(peerID.displayName)")
    }

    private func startBrowsing() {
        browser = MCNearbyServiceBrowser(
            peer: peerID,
            serviceType: serviceType
        )
        browser?.delegate = self
        browser?.startBrowsingForPeers()
        print("📱 iPhone browsing...")
    }

    func reconnect() {
        #if os(iOS)
        browser?.stopBrowsingForPeers()
        browser = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.startBrowsing()
        }
        #endif
    }

    // Appends timestamp so repeated commands always trigger onChange
    func send(_ command: String) {
        guard !session.connectedPeers.isEmpty else {
            print("⚠️ No connected peers")
            return
        }
        let message = "\(command)|\(Date().timeIntervalSince1970)"
        do {
            let data = Data(message.utf8)
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
            print("📤 Sent: \(message)")
        } catch {
            print("❌ Send error: \(error)")
        }
    }
}

// MARK: - MCSessionDelegate

extension SessionManager: MCSessionDelegate {

    func session(_ session: MCSession,
                 peer peerID: MCPeerID,
                 didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                self.connected = true
                print("✅ Connected to: \(peerID.displayName)")
            case .connecting:
                print("🟡 Connecting to: \(peerID.displayName)")
            case .notConnected:
                self.connected = false
                print("❌ Disconnected from: \(peerID.displayName)")
                self.reconnect()
            @unknown default:
                break
            }
        }
    }

    func session(_ session: MCSession,
                 didReceive data: Data,
                 fromPeer peerID: MCPeerID) {
        let msg = String(decoding: data, as: UTF8.self)
        DispatchQueue.main.async {
            print("📥 Received: \(msg)")
            self.receivedMessage = msg
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream,
                 withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension SessionManager: MCNearbyServiceAdvertiserDelegate {

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        print("📩 Invitation from: \(peerID.displayName) — accepting")
        invitationHandler(true, session)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didNotStartAdvertisingPeer error: Error) {
        print("❌ Advertiser failed: \(error)")
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension SessionManager: MCNearbyServiceBrowserDelegate {

    func browser(_ browser: MCNearbyServiceBrowser,
                 foundPeer peerID: MCPeerID,
                 withDiscoveryInfo info: [String: String]?) {
        print("🔍 Found: \(peerID.displayName) — inviting")
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 30)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("👋 Lost: \(peerID.displayName)")
    }

    func browser(_ browser: MCNearbyServiceBrowser,
                 didNotStartBrowsingForPeers error: Error) {
        print("❌ Browser failed: \(error)")
    }
}
