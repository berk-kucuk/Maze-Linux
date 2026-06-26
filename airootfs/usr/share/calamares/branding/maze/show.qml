/* Maze Linux — minimal OLED Calamares slideshow.
 * True-black background with a soft white glow and the install message.
 * Replace with a richer multi-slide deck later. */
import QtQuick 2.0
import calamares.slideshow 1.0

Presentation {
    id: presentation

    function onActivate() { timer.running = true; }
    function onLeave()    { timer.running = false; }

    Timer {
        id: timer
        interval: 30000
        running: false
        repeat: true
        onTriggered: presentation.goToNextSlide()
    }

    Slide {
        anchors.fill: parent

        Rectangle {
            anchors.fill: parent
            color: "#0e0e0e"

            // soft bloom (blur-like) bottom-right
            Rectangle {
                width: 520; height: 520; radius: 260
                anchors.right: parent.right; anchors.bottom: parent.bottom
                anchors.rightMargin: -120; anchors.bottomMargin: -120
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#1a1a1a" }
                    GradientStop { position: 1.0; color: "#0e0e0e" }
                }
                opacity: 0.6
            }

            Column {
                anchors.centerIn: parent
                spacing: 16
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Maze Linux"
                    color: "#ffffff"
                    font.pixelSize: 40
                    font.bold: true
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Privacy-first, AI-native desktop — installing…"
                    color: "#9a9aa6"
                    font.pixelSize: 16
                }
            }
        }
    }
}
