import AppKit

struct PasteboardSnapshot {
    private let itemData: [[NSPasteboard.PasteboardType: Data]]

    init(_ pasteboard: NSPasteboard) {
        itemData = pasteboard.pasteboardItems?.map { item in
            Dictionary(
                uniqueKeysWithValues: item.types.compactMap { type in
                    item.data(forType: type).map { (type, $0) }
                }
            )
        } ?? []
    }

    @discardableResult
    func restore(to pasteboard: NSPasteboard) -> Bool {
        let items = itemData.map { representations in
            let item = NSPasteboardItem()
            for (type, data) in representations {
                item.setData(data, forType: type)
            }
            return item
        }

        pasteboard.clearContents()
        guard !items.isEmpty else { return true }
        return pasteboard.writeObjects(items)
    }

    @discardableResult
    static func replaceString(
        _ text: String,
        on pasteboard: NSPasteboard,
        rollbackTo snapshot: PasteboardSnapshot? = nil
    ) -> Bool {
        let item = NSPasteboardItem()
        guard item.setString(text, forType: .string) else { return false }

        let rollbackSnapshot = snapshot ?? PasteboardSnapshot(pasteboard)
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else {
            rollbackSnapshot.restore(to: pasteboard)
            return false
        }
        return true
    }
}
