////
////  StreamListView.swift
////  iptv
////
////  Created by HOOGSTRAAT, JOSHUA on 02.09.25.
////
//
//import SwiftUI
//
//struct StreamListView: View {
//    let category: Category
//    
//    @Environment(Catalog.self) private var catalog
//    @Environment(Player.self) private var player
//    
//    @State private var fetching = true
//    @State private var error: String?
//
//    var body: some View {
//        Group {
//            if fetching {
//                ProgressView()
//            } else if let error {
//                Text(error)
//            } else {
//                List(catalog.seriesCatalog) { video in
//                    Button {
//                        Task {
//                            do {
//                                let url = try await catalog.resolveURL(for: video)
//                                player.load(video, url, presentation: .fullWindow)
//                            } catch {
//                                print(error)
//                            }
//                        }
//                    } label: {
//                        VideoTile(video: video)
//                    }
//                }
//            }
//        }
//        .onChange(of: category, initial: true) {
//            Task { await loadStreams() }
//        }
//    }
//
//    private func loadStreams() async {
//        fetching = true
//        error = nil
//        do {
//            try await catalog.getVodStreams(in: category)
//            fetching = false
//        } catch {
//            self.error = error.localizedDescription
//            fetching = false
//        }
//    }
//}
//
//#Preview {
//    StreamListView(category: .init(id: "test_id", name: "test_name"))
//}
