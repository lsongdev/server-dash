//
//  ServerView.swift
//  ServerDash
//
//  Created by Lakr Aream on 4/19/21.
//

import PTFoundation
import SwiftUI

struct ServerBoardView: View {
    private let agent = Agent.shared
    @State private var serverDescriptors = Agent.shared.serverDescriptorsSorted
    @State private var supervisedDescriptors = Agent.shared.serverDescriptorsSortedSupervised

    var body: some View {
        VStack {
            if supervisedDescriptors.isEmpty {
                NoServerGuider()
            } else {
                container
            }
        }
        .onReceive(agent.$serverDescriptorsSorted) { serverDescriptors = $0 }
        .onReceive(agent.$serverDescriptorsSortedSupervised) { supervisedDescriptors = $0 }
    }

    var container: some View {
        VStack{
            HStack {
                Image(systemName: "square.stack.3d.down.forward.fill")
                if serverDescriptors == supervisedDescriptors {
                    Text("SERVER STATUS")
                        .bold()
                } else {
                    HStack(alignment: .bottom) {
                        Text("SERVER STATUS")
                            .font(.system(size: 16, weight: .bold, design: .default))
                        Text("\(supervisedDescriptors.count)/\(serverDescriptors.count)")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                    }
                }
                Spacer()
                Group {
                    Button(action: {
                        DispatchQueue.global().async {
                            for server in PTServerManager.shared.obtainServerList() {
                                PTServerManager.shared.updateServerSupervisionInfoNow(withKey: server.uuid)
                            }
                        }
                    }, label: {
                        Text(NSLocalizedString("REFRESH_NOW", comment: "Refresh Now"))
                            .font(.system(size: 14, weight: .regular, design: .default))
                            .foregroundColor(.overridableAccentColor)
                    })
                }
                .font(.system(size: 18, weight: .regular, design: .default))
                .foregroundColor(.overridableAccentColor)
            }
            .font(.system(size: 15, weight: .regular, design: .default))
            Divider()
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300))]) {
                ForEach(supervisedDescriptors, id: \.self) { serverDescriptor in
                    ServerBlockView(serverDescriptor: serverDescriptor)
                        .frame(height: 140)
                }
            }
        }
        
    }
}

struct ServerBoardView_Previews: PreviewProvider {
    static var previews: some View {
        ServerBoardView()
            .previewLayout(.fixed(width: 600, height: 400))
    }
}
