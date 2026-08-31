import Foundation
import IOBluetooth

enum Probe {
    static func run() {
        fputs("Accentum probe — looking for paired Sennheiser devices…\n", stderr)
        let devices = SennheiserClient.candidateDevices()
        guard !devices.isEmpty else {
            fputs("No paired Sennheiser devices found.\n", stderr)
            exit(1)
        }
        for d in devices {
            let connected = d.isConnected() ? "connected" : "paired"
            fputs("  • \(d.name ?? "?") [\(d.addressString ?? "?")] (\(connected))\n", stderr)
            dumpServices(d)
        }
        let target = SennheiserClient.connectedAccentum() ?? devices[0]
        fputs("\nConnecting to \(target.name ?? "?")…\n", stderr)

        let client = SennheiserClient()
        var done = false
        var probeDone = false

        client.onChange = {
            if !client.lastError.isEmpty {
                fputs("  status: \(client.lastError)\n", stderr)
            }
            if client.isConnected && !done {
                done = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    printState(client)
                    probeDone = true
                }
            }
        }

        client.connect(to: target)
        let deadline = Date(timeIntervalSinceNow: 20)
        while !probeDone && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
        }
        if !probeDone {
            fputs("✗ Timeout (connected=\(client.isConnected), error='\(client.lastError)')\n", stderr)
            exit(1)
        }
        client.disconnect()
        fputs("\nDone.\n", stderr)
    }

    private static func dumpServices(_ dev: IOBluetoothDevice) {
        dev.performSDPQuery(nil)
        Thread.sleep(forTimeInterval: 2)
        guard let records = dev.services as? [IOBluetoothSDPServiceRecord] else {
            fputs("    (no SDP records)\n", stderr)
            return
        }
        for rec in records {
            var ch: BluetoothRFCOMMChannelID = 0
            let hasRfcomm = rec.getRFCOMMChannelID(&ch) == kIOReturnSuccess
            let name = rec.getServiceName() ?? "(unnamed)"
            fputs("    SDP: \(name) rfcomm=\(hasRfcomm ? String(ch) : "—")\n", stderr)
        }
    }

    private static func printState(_ client: SennheiserClient) {
        fputs("\n✓ Connected\n", stderr)
        fputs("  Model:    \(client.modelId)\n", stderr)
        fputs("  Firmware: \(client.firmware)\n", stderr)
        fputs("  Battery:  \(client.battery.map { "\($0)%" } ?? "—")\n", stderr)
        fputs("  Codec:    \(client.codec)\n", stderr)
        fputs("  Mode:     \(client.noise.active.rawValue)\n", stderr)
        fputs("  EQ:       \(client.eqPreset) \(client.eqBands)\n", stderr)
        fputs("  Bass:     \(client.bassBoost)\n", stderr)
    }
}
