import QtQuick

// Lush entrance: fade plus a slight settle in scale. OutQuint ends without
// passing the final value, so nothing bounces.
// Usage: LushAppear { target: root }
ParallelAnimation {
    id: appear

    property Item target: null

    running: true

    NumberAnimation { target: appear.target; property: "opacity"; from: 0; to: 1; duration: 520; easing.type: Easing.OutCubic }
    NumberAnimation { target: appear.target; property: "scale"; from: 0.975; to: 1; duration: 680; easing.type: Easing.OutQuint }
}
