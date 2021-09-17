//
//  NoServerGuider.swift
//  ServerDash
//
//  Created by Lakr Aream on 5/17/21.
//

import SwiftUI

struct NoServerGuider: View {
    let LSOperationAddServer = NSLocalizedString("ADD_SERVER", comment: "Add Server")

    var body: some View {
        Group{
            NavigationLink(destination: AddServerView()) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .foregroundColor(.lightGray)
                    HStack {
                        Image(systemName: "plus.viewfinder")
                        Text(LSOperationAddServer)
                    }
                }
            }
            .frame(height: 100)
        }
    }
}

struct NoServerGuider_Previews: PreviewProvider {
    static var previews: some View {
        NoServerGuider()
    }
}
