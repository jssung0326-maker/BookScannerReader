import Foundation
import Combine

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var books: [Book] = []
    @Published var lastErrorMessage: String?

    private let fm = FileManager.default

    init() {
        load()
    }

    func add(_ book: Book) {
        books.insert(book, at: 0)
        save()
    }

    func update(_ book: Book) {
        guard let index = books.firstIndex(where: { $0.id == book.id }) else { return }
        books[index] = book
        save()
    }

    func remove(at offsets: IndexSet) {
        let ids = Set(offsets.compactMap { index in
            books.indices.contains(index) ? books[index].id : nil
        })
        removeBooks(withIDs: ids)
    }

    func removeBooks(withIDs ids: Set<UUID>) {
        guard !ids.isEmpty else { return }

        for book in books where ids.contains(book.id) {
            let directory = StoragePaths.bookDirectory(bookID: book.id)
            if fm.fileExists(atPath: directory.path) {
                do {
                    try fm.removeItem(at: directory)
                } catch {
                    lastErrorMessage = "책 파일을 삭제하지 못했습니다: \(error.localizedDescription)"
                    return
                }
            }
        }

        books.removeAll { ids.contains($0.id) }
        save()
    }

    func book(with id: UUID) -> Book? {
        books.first(where: { $0.id == id })
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: StoragePaths.libraryFile.path) else { return }
        do {
            let data = try Data(contentsOf: StoragePaths.libraryFile)
            books = try JSONDecoder.bookDecoder.decode([Book].self, from: data)
        } catch {
            books = []
            lastErrorMessage = "서재 정보를 읽지 못했습니다. 기존 파일은 삭제하지 않았습니다: \(error.localizedDescription)"
        }
    }

    private func save() {
        do {
            try fm.createDirectory(at: StoragePaths.booksDirectory, withIntermediateDirectories: true)
            let data = try JSONEncoder.bookEncoder.encode(books)
            try data.write(to: StoragePaths.libraryFile, options: .atomic)
        } catch {
            lastErrorMessage = "서재 정보를 저장하지 못했습니다: \(error.localizedDescription)"
            print("Library save failed: \(error)")
        }
    }
}

private extension JSONEncoder {
    static var bookEncoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

private extension JSONDecoder {
    static var bookDecoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
