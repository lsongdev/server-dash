import XCTest
@testable import PTFoundation

final class DarwinSnapshotTests: XCTestCase {
    func testMacSnapshotPopulatesExistingDashboardModel() throws {
        let bootTime = Int(Date().timeIntervalSince1970) - 3600
        let snapshot = """
        __SERVER_DASH_TOP__
        Processes: 100 total, 2 running, 98 sleeping, 500 threads
        Load Avg: 1.25, 1.50, 1.75
        CPU usage: 12.5% user, 7.5% sys, 80.0% idle
        __SERVER_DASH_MEMORY__
        17179869184
        Mach Virtual Memory Statistics: (page size of 16384 bytes)
        Pages free: 100000.
        Pages inactive: 200000.
        Pages speculative: 10000.
        total = 2.00G used = 1.00G free = 1.00G
        __SERVER_DASH_FILESYSTEM__
        Filesystem 1024-blocks Used Available Capacity Mounted on
        /dev/disk3s5 100000 40000 60000 40% /System/Volumes/Data
        __SERVER_DASH_HOSTNAME__
        mac-mini.local
        __SERVER_DASH_UPTIME__
        { sec = \(bootTime), usec = 0 }
        __SERVER_DASH_RELEASE__
        27.0
        __SERVER_DASH_NET_0__
        Name Mtu Network Address Ipkts Ierrs Ibytes Opkts Oerrs Obytes Coll
        en0 1500 <Link#7> aa:bb:cc:dd:ee:ff 10 0 1000 20 0 2000 0
        __SERVER_DASH_NET_1__
        Name Mtu Network Address Ipkts Ierrs Ibytes Opkts Oerrs Obytes Coll
        en0 1500 <Link#7> aa:bb:cc:dd:ee:ff 12 0 1200 25 0 2500 0
        __SERVER_DASH_END__
        """

        let info = try XCTUnwrap(PTSSHClient.shared.buildDarwinServerInfo(intake: snapshot))
        XCTAssertEqual(info.ServerSystemInfo.releaseName, "macOS 27.0")
        XCTAssertEqual(info.ServerSystemInfo.hostname, "mac-mini.local")
        XCTAssertEqual(info.ServerSystemInfo.runningProcs, 2)
        XCTAssertEqual(info.ServerSystemInfo.totalProcs, 100)
        XCTAssertEqual(info.ServerSystemInfo.load1, 1.25)
        XCTAssertEqual(info.ServerSystemInfo.uptimeSec, 3600, accuracy: 2)
        XCTAssertEqual(info.ServerProcessInfo.summary.sumUsed, 20)
        XCTAssertTrue(info.ServerProcessInfo.cores.isEmpty)
        XCTAssertEqual(info.ServerMemoryInfo.memTotal, 16_777_216)
        XCTAssertGreaterThan(info.ServerMemoryInfo.phyUsed, 0)
        XCTAssertEqual(info.ServerFileSystemInfo.first?.mountPoint, "/")
        XCTAssertEqual(info.ServerFileSystemInfo.first?.usedPercent, 40)
        XCTAssertEqual(info.ServerNetworkInfo.first?.device, "en0")
        XCTAssertEqual(info.ServerNetworkInfo.first?.rxBytesPerSec, 200)
        XCTAssertEqual(info.ServerNetworkInfo.first?.txBytesPerSec, 500)
    }

    func testMacSnapshotRequiresCpuAndMemory() {
        XCTAssertNil(PTSSHClient.shared.buildDarwinServerInfo(intake: "__SERVER_DASH_END__"))
    }

    #if os(macOS)
    func testCollectorParsesLocalMac() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", PTSSHClient.ScriptCollection.obtainDarwinSnapshot.rawValue]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
        let snapshot = try XCTUnwrap(String(data: data, encoding: .utf8))
        let info = try XCTUnwrap(PTSSHClient.shared.buildDarwinServerInfo(intake: snapshot))
        XCTAssertTrue(info.ServerSystemInfo.releaseName.hasPrefix("macOS "))
        XCTAssertGreaterThan(info.ServerMemoryInfo.memTotal, 0)
        XCTAssertGreaterThanOrEqual(info.ServerProcessInfo.summary.sumUsed, 0)
        XCTAssertFalse(info.ServerFileSystemInfo.isEmpty)
        XCTAssertFalse(info.ServerNetworkInfo.isEmpty)
    }
    #endif
}
