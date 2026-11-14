import QtQuick
import "../common"

// File Dock, Atelier: the Restrained tiles on the card of the chosen Atelier style.
FileDockStyledFace {
    id: root
    look: "atelier"
    AtelierAppear { target: root; kit: AtelierKit { style: root.faceStyle } }
}
