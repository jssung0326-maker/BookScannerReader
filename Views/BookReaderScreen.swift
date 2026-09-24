import SwiftUI

struct BookReaderScreen: View {
    let book: Book
    @StateObject private var speech = SpeechService()
    @State private var pages: [PageRecord] = []
    @State private var pageIndex = 0

    private let pageStore = PageStore()

    var body: some View {
        Group {
            if let relative = book.pdfRelativePath {
                PDFReaderView(url: StoragePaths.bookDirectory(bookID: book.id).appendingPathComponent(relative), initialPageIndex: book.currentPageIndex)
            } else if !pages.isEmpty {
                scannedPageReader
            } else {
                ContentUnavailableView("읽을 페이지가 없습니다", systemImage: "book.closed")
            }
        }
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            pages = pageStore.loadPages(bookID: book.id)
            pageIndex = min(max(book.currentPageIndex, 0), max(pages.count - 1, 0))
        }
        .toolbar {
            if !pages.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(speech.isSpeaking ? "정지" : "읽어주기") {
                        if speech.isSpeaking {
                            speech.stop()
                        } else {
                            speech.speak(pages[pageIndex].ocrText)
                        }
                    }
                }
            }
        }
    }

    private var scannedPageReader: some View {
        VStack(spacing: 10) {
            if let image = pageStore.image(bookID: book.id, relativePath: pages[pageIndex].imageRelativePath) {
                GeometryReader { proxy in
                    ScrollView([.horizontal, .vertical]) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(minWidth: proxy.size.width, minHeight: proxy.size.height)
                    }
                }
            }

            HStack {
                Button("이전") { pageIndex = max(0, pageIndex - 1) }
                    .disabled(pageIndex == 0)
                Spacer()
                Text("\(pageIndex + 1) / \(pages.count)")
                Spacer()
                Button("다음") { pageIndex = min(pages.count - 1, pageIndex + 1) }
                    .disabled(pageIndex >= pages.count - 1)
            }
            .padding(.horizontal)
        }
    }
}
