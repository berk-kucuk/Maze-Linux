// Maze Linux — true-black OLED Plasma splash (login -> desktop).
// The splash loader sizes this root to the screen and drives `stage` 0..6
// as Plasma starts up; we map that to a thin progress bar under the logo.
import QtQuick 2.15

Rectangle {
    id: root
    color: "#000000"

    property int stage

    onStageChanged: {
        if (stage === 1) {
            introAnimation.running = true;
        }
    }

    // Maze simple logo only — no wordmark text.
    Image {
        id: logo
        anchors.centerIn: parent
        source: "logo.png"
        sourceSize.width: 128
        sourceSize.height: 128
        smooth: true
        opacity: 0
        scale: 0.92
    }

    // Thin progress bar near the lower third.
    Rectangle {
        id: track
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.height * 0.18
        width: 220
        height: 3
        radius: 2
        color: "#1affffff"
        opacity: logo.opacity

        Rectangle {
            height: parent.height
            radius: 2
            color: "#ffffff"
            width: parent.width * Math.min(root.stage / 6, 1)
            Behavior on width {
                NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
            }
        }
    }

    ParallelAnimation {
        id: introAnimation
        running: false
        NumberAnimation {
            target: logo; property: "opacity"
            from: 0; to: 1; duration: 600; easing.type: Easing.InOutQuad
        }
        NumberAnimation {
            target: logo; property: "scale"
            from: 0.92; to: 1; duration: 600; easing.type: Easing.OutCubic
        }
    }
}
