import QtQuick
import QtQuick.Controls

Rectangle {
    id: cardRoot
    property string text
    signal clicked()

    radius: 8
    color: cardMouse.containsMouse ? "#F0F7FF" : "#FAFAFA"
    border.color: cardMouse.containsMouse ? "#B8D4FF" : "#E5E7EB"
    border.width: 1

    Behavior on color { ColorAnimation { duration: 150 } }
    Behavior on border.color { ColorAnimation { duration: 150 } }

    Text {
        anchors.centerIn: parent
        text: cardRoot.text
        font.family: "Microsoft YaHei"
        font.pixelSize: 15
        color: "#1B263B"
    }

    MouseArea {
        id: cardMouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: cardRoot.clicked()
    }
}
