import QtQml

// Main's root: holds the parts' windows and helpers without being an Item
// (Qt 6.7+ embeds a Window declared inside an Item into that item's
// window, and Main's root has none, so the parts would never show).
QtObject {
    default property list<QtObject> contents
}
