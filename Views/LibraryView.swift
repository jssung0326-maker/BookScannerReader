import SwiftUI
import UniformTypeIdentifiers
import PDFKit

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var showNewScan = false
    @State private var showPDFImporter = false
    @State private var importError: String?

    private let pdfService = PDFService()

    var body: some View {
        NavigationStack {
            List {
                if library.books.isEmpty {
                    ContentUnavailableView(
                        "아직 책이 없습니다",
                        systemImage: "books.vertical",
                        description: Text("책을 스캔하거나 PDF를 가져오세요.")
                    )
                } else {
                    ForEach(library.books) { book in
                        NavigationLink(value: book) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(book.title).font(.headline)
                                Text("\(book.pageCount)페이지")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete(perform: library.remove)
                }
            }
            .navigationTitle("내 서재")
            .navigationDestination(for: Book.self) { book in
                BookReaderScreen(book: book)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showNewScan = true
                        } label: {
                            Label("책 스캔", systemImage: "camera")
                        }

                        Button {
                            showPDFImporter = true
                        } label: {
                            Label("PDF 가져오기", systemImage: "doc")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showNewScan) {
                NewScanBookView()
                    .environmentObject(library)
            }
            .fileImporter(
                isPresented: $showPDFImporter,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in
                importPDF(result)
            }
            .alert("PDF 가져오기 실패", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(importError ?? "알 수 없는 오류")
            }
        }
    }

    private func importPDF(_ result: Result<[URL], Error>) {
        do {
            guard let source = try result.get().first else { return }
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }

            let id = UUID()
            _ = try pdfService.copyImportedPDF(from: source, bookID: id)
            let doc = PDFDocument(url: StoragePaths.pdfURL(bookID: id))
            let title = source.deletingPathExtension().lastPathComponent
            let book = Book(id: id, title: title, pageCount: doc?.pageCount ?? 0, pdfRelativePath: "book.pdf")
            library.add(book)
        } catch {
            importError = error.localizedDescription
        }
    }
}
