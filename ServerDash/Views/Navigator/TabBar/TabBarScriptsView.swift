//
//  TabBarScriptView.swift
//  ServerDash
//
//  Created by Lakr Aream on 2021/4/29.
//

import SwiftUI

struct TabBarScriptsView: View {
    @State var presentCreate: Bool = false

    var body: some View {
        NavigationView {
            ScrollView {
                ScriptCollectionView()
                    .padding()
                    .background(
                        NavigationLink(
                            destination: ScriptCreateView(),
                            isActive: $presentCreate,
                            label: {
                                Text("").hidden()
                            }
                        )
                        .opacity(0)
                    )
            }
            .navigationBarItems(trailing: Group {
                Button(action: {
                    presentCreate = true
                }, label: {
                    Text(NSLocalizedString("CREATE_SCRIPT", comment: "Create Script"))
                })
            })
            .navigationTitle(NSLocalizedString("DOCK_SCRIPTS", comment: "Scripts"))
        }
    }
}

struct TabBarScriptsView_Previews: PreviewProvider {
    static var previews: some View {
        TabBarScriptsView()
    }
}
