// Maze Linux — true-black OLED SDDM login theme.
// Pure QtQuick + Controls so every pixel is themeable; only the SDDM context
// objects (sddm, config, userModel, sessionModel, keyboard) are used.
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: root
    width: 1920
    height: 1080
    color: "#000000"

    LayoutMirroring.enabled: Qt.locale().textDirection === Qt.RightToLeft
    LayoutMirroring.childrenInherit: true

    property int sessionIndex: sessionCombo.currentIndex

    function doLogin() {
        errorLabel.text = ""
        sddm.login(username.text, password.text, root.sessionIndex)
    }

    // --- Pure-black OLED backdrop with a whisper of vertical depth ---------
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#070708" }
            GradientStop { position: 0.5; color: "#000000" }
            GradientStop { position: 1.0; color: "#070708" }
        }
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            errorLabel.text = "Authentication failed — try again"
            password.text = ""
            password.forceActiveFocus()
        }
        function onLoginSucceeded() {}
    }

    // --- Live clock, top centre -------------------------------------------
    QtObject { id: timeSource; property var now: new Date() }
    Timer { interval: 1000; running: true; repeat: true; onTriggered: timeSource.now = new Date() }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 72
        spacing: 4
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            color: "#f2f3f5"
            font.pixelSize: 68
            font.weight: Font.Light
            text: Qt.formatDateTime(timeSource.now, "HH:mm")
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            color: "#9aa0aa"
            font.pixelSize: 16
            text: Qt.formatDateTime(timeSource.now, "dddd, d MMMM yyyy")
        }
    }

    // --- Login card --------------------------------------------------------
    Rectangle {
        id: card
        width: 360
        height: cardCol.implicitHeight + 60
        anchors.centerIn: parent
        radius: 18
        color: "#060608"
        border.color: "#26ffffff"
        border.width: 1

        ColumnLayout {
            id: cardCol
            width: parent.width - 56
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 30
            spacing: 14

            Image {
                source: "assets/logo.png"
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 84
                Layout.preferredHeight: 84 * (sourceSize.height > 0 ? sourceSize.height / sourceSize.width : 1)
                fillMode: Image.PreserveAspectFit
                smooth: true
            }

            Text {
                text: "Maze Linux"
                Layout.alignment: Qt.AlignHCenter
                color: "#f2f3f5"
                font.pixelSize: 22
                font.bold: true
            }
            Text {
                text: sddm.hostName
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: 4
                color: "#7a7f88"
                font.pixelSize: 12
            }

            TextField {
                id: username
                Layout.fillWidth: true
                implicitHeight: 44
                text: userModel.lastUser
                placeholderText: "Username"
                color: "#f2f3f5"
                placeholderTextColor: "#7a7f88"
                font.pixelSize: 15
                leftPadding: 14
                selectionColor: "#3c78ff"
                selectedTextColor: "#ffffff"
                background: Rectangle {
                    radius: 10
                    color: "#10ffffff"
                    border.width: 1
                    border.color: username.activeFocus ? "#ffffff" : "#26ffffff"
                }
                onAccepted: password.forceActiveFocus()
            }

            TextField {
                id: password
                Layout.fillWidth: true
                implicitHeight: 44
                echoMode: TextInput.Password
                placeholderText: "Password"
                color: "#f2f3f5"
                placeholderTextColor: "#7a7f88"
                font.pixelSize: 15
                leftPadding: 14
                selectionColor: "#3c78ff"
                selectedTextColor: "#ffffff"
                background: Rectangle {
                    radius: 10
                    color: "#10ffffff"
                    border.width: 1
                    border.color: password.activeFocus ? "#ffffff" : "#26ffffff"
                }
                onAccepted: root.doLogin()
            }

            Text {
                id: capsHint
                Layout.fillWidth: true
                visible: keyboard.capsLock
                text: "⚠  Caps Lock is on"
                color: "#e6b450"
                font.pixelSize: 11
            }

            Text {
                id: errorLabel
                Layout.fillWidth: true
                visible: text.length > 0
                text: ""
                color: "#e06666"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }

            Button {
                id: loginButton
                Layout.fillWidth: true
                implicitHeight: 44
                text: "Log In"
                onClicked: root.doLogin()
                contentItem: Text {
                    text: loginButton.text
                    color: "#0a0a0c"
                    font.pixelSize: 15
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    radius: 11
                    color: loginButton.down ? "#d8d8d8" : "#ffffff"
                }
            }

            Item { Layout.preferredHeight: 6 }
        }
    }

    // --- Bottom bar: session selector + power controls ---------------------
    Item {
        id: bottomBar
        height: 56
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 28
        anchors.rightMargin: 28

        RowLayout {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Text {
                text: "Session"
                color: "#9aa0aa"
                font.pixelSize: 13
            }
            ComboBox {
                id: sessionCombo
                Layout.preferredWidth: 220
                model: sessionModel
                textRole: "name"
                currentIndex: sessionModel.lastIndex
                font.pixelSize: 13
                background: Rectangle {
                    radius: 9
                    color: "#10ffffff"
                    border.width: 1
                    border.color: "#26ffffff"
                }
                contentItem: Text {
                    leftPadding: 12
                    text: sessionCombo.displayText
                    color: "#f2f3f5"
                    font.pixelSize: 13
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }
            }
        }

        RowLayout {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            component PowerButton: Button {
                id: pb
                flat: true
                implicitHeight: 38
                property color labelColor: "#cfd3da"
                contentItem: Text {
                    text: pb.text
                    color: pb.down ? "#ffffff" : pb.labelColor
                    font.pixelSize: 13
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: 12
                    rightPadding: 12
                }
                background: Rectangle {
                    radius: 9
                    color: pb.down ? "#1affffff" : (pb.hovered ? "#12ffffff" : "transparent")
                }
            }

            PowerButton {
                text: "Suspend"
                visible: sddm.canSuspend
                onClicked: sddm.suspend()
            }
            PowerButton {
                text: "Restart"
                visible: sddm.canReboot
                onClicked: sddm.reboot()
            }
            PowerButton {
                text: "Shut Down"
                labelColor: "#e58a8a"
                visible: sddm.canPowerOff
                onClicked: sddm.powerOff()
            }
        }
    }

    Component.onCompleted: {
        if (username.text === "")
            username.forceActiveFocus()
        else
            password.forceActiveFocus()
    }
}
