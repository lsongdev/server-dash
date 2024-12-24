//
//  ScriptGridView.swift
//  ServerDash
//
//  Created by Innei on 2021/5/5.
//

import PTFoundation
import SwiftUI

struct ScriptListView: View {
    let insideServer: PTServerManager.ServerDescriptor?
    init(withInServer server: PTServerManager.ServerDescriptor? = nil) {
        insideServer = server
    }

    @State var presentCreate: Bool = false
    @StateObject var windowObserver = WindowObserver()
    @ObservedObject var agent = Agent.shared
    
    
    @State var dataSource: [IterationElement] = []

    struct IterationElement: Identifiable {
        var id: String {
            section + String(describing: scripts)
        }

        let section: String
        let scripts: [CodeClip]
        init(section: String, scripts: [String: CodeClip]) {
            self.section = section
            self.scripts = PTCodeClipManager.shared.obtainBuiltinCodeClips()
        }
    }

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect() // TODO:

    var body: some View {
        ScrollView{
            VStack {
                Group {
                    if dataSource.count < 1 {
                        NavigationLink(destination: ScriptCreateView()) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .foregroundColor(.lightGray)
                                HStack {
                                    Image(systemName: "plus.viewfinder")
                                    Text(NSLocalizedString("Add Script", comment: "Add Script"))
                                }
                            }
                        }
                        .frame(height: 100)
                    } else {
                        ForEach(dataSource) { element in
                            Section(
                                header: HStack{
                                    Text(element.section).bold()
                                    Spacer()
                                    NavigationLink(destination: ScriptCreateView(initData: .init(name: "", section: element.section, icon: "", code: ""))) {
                                        Image(systemName: "plus.circle")
                                    }
                                    
                                }
                            ) {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                                    ForEach(element.scripts, id: \.self) { script in
                                        if insideServer != nil {
                                            ScriptItemView(clip: script, useDoubleTap: false)
                                                .onTapGesture {
                                                    execute(withClip: script)
                                                }
                                        } else {
                                            NavigationLink(
                                                destination: ScriptPreExecView(clip: script),
                                                label: {
                                                    ScriptItemView(clip: script)
                                                }
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding()
        }
        
        .onReceive(agent.$clipDataTokenPublisher) { _ in
            updateDataSource()
        }
        .onAppear {
            updateDataSource()
        }
        .background(
            HostingWindowFinder { [weak windowObserver] window in
                windowObserver?.window = window
            }
        )
        .sheet(isPresented: $presentCreate){
            NavigationView {
                ScriptCreateView()
            }
        }
        .navigationBarItems(trailing: Group {
            Button(action: {
                presentCreate.toggle()
            }, label: {
                Image(systemName: "plus")
            })
        })
        .navigationTitle(NSLocalizedString("SIDEBAR_CODE_CLIP", comment: "Script"))
    }

    func updateDataSource() {
        var clips = PTCodeClipManager
            .shared
            .obtainCodeClipList()
        if NSLocalizedString("DEFAULT_SECTION_NAME", comment: "Default").count > 0,
           let defaults = clips[PTCodeClipManager.defaultSectionName],
           defaults.count > 0
        {
            clips.removeValue(forKey: PTCodeClipManager.defaultSectionName)
            clips[NSLocalizedString("DEFAULT_SECTION_NAME", comment: "Default")] = defaults
        }
        dataSource = clips
            .map { key, value in
                IterationElement(section: key, scripts: value)
            }
            .sorted { $0.section < $1.section }
    }

    func execute(withClip clip: CodeClip) {
        let view = ScriptExecution(clip: clip, serverDescriptor: insideServer)
        let controller = UIHostingController(rootView: view)
        (controller as UIViewController).modalPresentationStyle = .formSheet
        (controller as UIViewController).preferredContentSize = CGSize(width: 800, height: 600)
        windowObserver.window?.topMostViewController?.present(controller, animated: true, completion: {})
    }
}

struct ScriptListView_Previews: PreviewProvider {
    static var previews: some View {
        ScriptListView().previewLayout(.fixed(width: 500, height: 800))
    }
}
