import Foundation
import Combine

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var books: [Book] = []

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
        for index in offsets {
            let book = books[index]
            try? fm.removeItem(at: StoragePaths.bookDirectory(bookID: book.id))
        }
        for index in offsets.sorted(by: >) {
            books.remove(at: index)
        }
        save()
    }

    func book(with id: UUID) -> Book? {
        books.first(where: { $0.id == id })
    }

    private func load() {
        guard let data = try? Data(contentsOf: StoragePaths.libraryFile) else { return }
        books = (try? JSONDecoder.bookDecoder.decode([Book].self, from: data)) ?? []
    }

    private func save() {
        do {
            try fm.createDirectory(at: StoragePaths.booksDirectory, withIntermediateDirectories: true)
            let data = try JSONEncoder.bookEncoder.encode(books)
            try data.write(to: StoragePaths.libraryFile, options: .atomic)
        } catch {
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
