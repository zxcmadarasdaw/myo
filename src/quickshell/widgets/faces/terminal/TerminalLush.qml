import QtQuick
import "../common"

// Terminal, Lush: ornamented glass card that brightens while the terminal has focus.
TerminalStyledFace {
    id: root
    look: "lush"
    LushAppear { target: root }
}
