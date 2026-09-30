//
//  DashboardView.swift
//  ServerDash
//
//  Created by Lakr Aream on 4/19/21.
//

import PTFoundation
import SwiftUI

struct DashboardView: View {
    @State var shouldOpenAddSheet: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                GatheringDataView()
                ServerBoardView()
            }.padding()
        }
        .sheet(isPresented: $shouldOpenAddSheet){
            NavigationView {
                AddServerView()
            }
        }
        .navigationTitle("Dashboard")
        .navigationViewStyle(StackNavigationViewStyle())
        .navigationBarItems(trailing: Group {
            Button(action: {
                shouldOpenAddSheet.toggle()
            }, label: {
                Image(systemName: "plus")
            })
        })
    }
}

struct DashboardView_Previews: PreviewProvider {
    static var previews: some View {
        DashboardView()
    }
}
