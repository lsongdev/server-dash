//
//  NoServerGuider.swift
//  ServerDash
//
//  Created by Lakr Aream on 5/17/21.
//

import SwiftUI

struct NoServerGuider: View {
    var body: some View {
        Group{
            NavigationLink(destination: AddServerView()) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .foregroundColor(.lightGray)
                    HStack {
                        Image(systemName: "plus.viewfinder")
                        Text("Add Server")
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
