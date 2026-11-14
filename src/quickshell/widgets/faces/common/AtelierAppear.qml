import QtQuick

// Entrance of an Atelier face: a fade with a slight settle. With motion "off" (or
// performance mode) both durations are 0 and the face simply appears.
// Usage: AtelierAppear { target: root; kit: kit }
ParallelAnimation {
    id: appear
    property Item target: null
    property AtelierKit kit: null
    running: true

    NumberAnimation {
        target: appear.target
        property: "opacity"
        from: 0
        to: 1
        duration: appear.kit ? appear.kit.duration(380) : 0
        easing.type: Easing.OutCubic
    }
    NumberAnimation {
        target: appear.target
        property: "scale"
        from: 0.975
        to: 1
        duration: appear.kit ? appear.kit.duration(460) : 0
        easing.type: Easing.OutQuint
    }
}
