//
//  TabBarBoardView.swift
//  ServerDash
//
//  Created by Lakr Aream on 2021/4/29.
//

import PTFoundation
import SwiftUI

struct TabBarBoardView: View {
    let LSNavTitle = NSLocalizedString("APP_NAME", comment: "Board")

    @State var shouldOpenAddSheet: Bool = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 10) {
                    GatheringDataView()
                    ServerBoardView()
                }.padding(.horizontal)
            }
            .navigationTitle(LSNavTitle)
            .navigationBarItems(trailing: Group {
                Button(action: {
                    shouldOpenAddSheet.toggle()
                }, label: {
                    Image(systemName: "plus")
                })
            })
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

struct TabBarBoardView_Previews: PreviewProvider {
    static var previews: some View {
        TabBarBoardView()
    }
}
