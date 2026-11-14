import QtQuick
import "../common"

// GitHub, Lush: the contribution graph in a mauve-to-blue ramp with rounded
// cells, on ornamented glass (see the `look` property of GithubFace).
GithubFace {
    id: root
    look: "lush"

    LushCard { z: -1; anchors.fill: parent; intensity: 0.6 }
    LushAppear { target: root }
}
