//
//  DashboardView.swift
//  ServerDash
//
//  Created by Lakr Aream on 4/19/21.
//

import PTFoundation
import SwiftUI

struct DashboardView: View {
    let LSNavTitle = NSLocalizedString("NAV_TITLE_BOARD", comment: "Board")

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                GatheringDataView()
                ServerBoardView()
            }.padding()
        }
        .navigationTitle(LSNavTitle)
    }
}

struct DashboardView_Previews: PreviewProvider {
    static var previews: some View {
        DashboardView()
    }
}
