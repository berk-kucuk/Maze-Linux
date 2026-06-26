/*
 * Maze Panic — Plasma 6 system-tray widget.
 *
 * This is a Plasma plasmoid (a widget hosted by plasmashell), NOT a standalone
 * Qt app. All privileged work is done by the maze-guardd daemon; this widget
 * only launches the unprivileged front-end scripts:
 *   * maze-panic          — wipe traces, cut network, lock
 *   * maze-panic-restore  — bring the network back (undo the reversible part)
 *
 * Right-click the tray icon for both actions; left-click opens a small panel.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // Monochrome WHITE shield icon shipped with the widget (not a coloured theme
    // icon), to suit the dark Maze panel.
    readonly property string panicIcon: "/usr/share/plasma/plasmoids/com.mazelinux.panic/contents/icons/maze-panic.svg"

    Plasmoid.icon: panicIcon
    // Always visible in the system tray (never auto-hidden into the overflow).
    Plasmoid.status: PlasmaCore.Types.ActiveStatus
    toolTipMainText: i18n("Maze Panic")
    toolTipSubText: i18n("Wipe traces, cut network and lock — or restore the network")

    // Run the unprivileged front-end scripts (they talk to maze-guardd).
    Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => disconnectSource(sourceName)
        function exec(cmd) { if (cmd) connectSource(cmd); }
    }
    function panic()   { executable.exec("/usr/local/bin/maze-panic"); }
    function restore() { executable.exec("/usr/local/bin/maze-panic-restore"); }

    // Right-click context menu.
    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Activate Panic Mode")
            icon.name: "security-high"
            onTriggered: root.panic()
        },
        PlasmaCore.Action {
            text: i18n("Restore network (undo panic)")
            icon.name: "network-connect"
            onTriggered: root.restore()
        }
    ]

    // Tray icon: click toggles the small panel.
    compactRepresentation: MouseArea {
        id: compact
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        onClicked: root.expanded = !root.expanded
        Kirigami.Icon {
            anchors.fill: parent
            source: root.panicIcon
            active: compact.containsMouse
        }
    }

    // Click panel: a description plus the two big buttons.
    fullRepresentation: ColumnLayout {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 17
        Layout.minimumHeight: Kirigami.Units.gridUnit * 11
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Heading {
            level: 3
            text: i18n("Maze Panic")
        }
        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: i18n("Immediately cuts all network, wipes system logs, shell history and the clipboard, and locks the screen. Your files and the encrypted disk are NOT touched.")
        }
        QQC2.Button {
            Layout.fillWidth: true
            icon.name: "security-high"
            text: i18n("Activate Panic Mode")
            onClicked: { root.panic(); root.expanded = false; }
        }
        QQC2.Button {
            Layout.fillWidth: true
            icon.name: "network-connect"
            text: i18n("Restore network (undo panic)")
            onClicked: { root.restore(); root.expanded = false; }
        }
        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            opacity: 0.7
            font: Kirigami.Theme.smallFont
            text: i18n("Restore brings back Wi-Fi/mobile; wiped logs and history stay cleared.")
        }
        Item { Layout.fillHeight: true }
    }
}
