//
//  DetailedFileSystem.swift
//  ServerDash
//
//  Created by Lakr Aream on 5/20/21.
//

import PTFoundation
import SwiftUI

struct DetailedFileSystemView: View {
    let data: [PTServerManager.ServerFileSystemInfo]
    var body: some View {
        VStack {
            HStack {
                Image(systemName: "internaldrive")
                Text("DISK")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Spacer()
            }
            Divider()
            VStack(spacing: 12) {
                ForEach(0 ..< data.count, id: \.self) { idx in
                    VStack(spacing: 6) {
                        HStack {
                            Text(data[idx].mountPoint)
                                .font(.system(size: 12, weight: .bold, design: .default))
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text(String(format: " %.2f", data[idx].usedPercent) + " %")
                                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                                    .foregroundColor(data[idx].usedPercent > 75 ? .red : .blue)
                                Text(String(
                                    format: "USED: %@ FREE %@",
                                    bytesDescription(bytes: data[idx].usedBytes),
                                    bytesDescription(bytes: data[idx].freeBytes)
                                ))
                            }
                            .font(.system(size: 8, weight: .regular, design: .monospaced))
                        }

                        SeparatedProgressView(height: 25,
                                              backgroundColor: .systemGray5,
                                              rounded: false,
                                              progressElements: [
                                                  (.yellow, Float(data[idx].usedBytes)),
                                              ],
                                              emptyHolder: Float(data[idx].freeBytes))
                            .cornerRadius(5)
                    }
                }
            }
            Divider()
            HStack {
                Text(NSLocalizedString("MOUNTPOINT_INACCURATE_WARNING", comment: "Mount point may be inaccurate due to system limit")).font(.system(size: 8, weight: .regular, design: .monospaced))
                Spacer()
            }
            .opacity(0.5)
        }
        .padding()
        .background(Color.lightGray)
        .cornerRadius(12)
    }
    
    func bytesDescription(bytes: Float) -> String {
        let kilobyte: Float = 1024.00
        let megabyte = kilobyte * kilobyte
        let gigabyte = megabyte * kilobyte
        
        if bytes >= gigabyte {
            return String(format: "%.2f GB", bytes / gigabyte)
        } else if bytes >= megabyte {
            return String(format: "%.2f MB", bytes / megabyte)
        } else if bytes >= kilobyte {
            return String(format: "%.2f KB", bytes / kilobyte)
        }
        return "\(bytes) B"
    }

}
