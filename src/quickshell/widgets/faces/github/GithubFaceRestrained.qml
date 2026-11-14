import QtQuick
import "../common"

// GitHub, Restrained: the contribution graph as a quiet monochrome ramp with
// square cells on a flat hairline card (see the `look` property of GithubFace).
GithubFace {
    id: root
    look: "restrained"

    MinimalCard { z: -1; anchors.fill: parent }
    MinimalAppear { target: root }
}
