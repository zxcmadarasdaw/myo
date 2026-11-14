import QtQuick

// Restrained entrance: a short fade, no movement, no overshoot.
// Usage: MinimalAppear { target: root }
NumberAnimation {
    property: "opacity"
    from: 0
    to: 1
    duration: 240
    easing.type: Easing.OutCubic
    running: true
}
