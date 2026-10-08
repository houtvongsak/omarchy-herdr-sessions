import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

// Herdr sessions on this computer and on other machines, one tab per machine.
// Remote machines come from bin/herdr-sessions-data, which asks each one over SSH.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property string filterText: ""
  property bool searching: false
  property int selectedIndex: 0
  property bool cursorActive: false

  // This computer's sessions, as `herdr session list --json` gives them.
  property var sessions: []
  property string hostName: ""
  // Other machines, in list order: {target, key, label, loaded, ok, error, sessions}.
  property var machines: []
  // Sessions this computer's herdr clients are showing: {key, session}, key "" for local.
  property var attached: []
  property int tabIndex: 0

  // "" (the list), "session" (new session form) or "machine" (add machine form).
  property string formMode: ""
  // What the confirm dialog is about: {kind: "delete"|"remove", target, name}.
  property var pendingConfirm: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string dataScript: decodeURIComponent(String(Qt.resolvedUrl("bin/herdr-sessions-data")).replace(/^file:\/\//, ""))
  readonly property var currentTab: root.tabAt(root.tabIndex)

  // Shares the [menu] surface tokens, like the built-in clipboard picker,
  // so themes that style the menu also style this picker.
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int contentSpacing: Style.spacing.md
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int tabsHeight: Style.font.body + Style.spacing.controlPaddingY * 2
  property int footerHeight: Style.font.caption + Style.spacing.sm * 2
  property int rowHeight: Math.max(Style.space(50), Style.font.title + Style.font.caption + Style.spacing.rowPaddingX * 2)
  property int rowPadding: Style.spacing.rowPaddingX
  property int markerWidth: Style.space(16)
  property int cardWidth: Math.min(Style.space(680), panel.width - Style.gapsOut * 2)
  property int listRows: Math.max(4, displayModel.count)
  property int contentHeight: root.headerHeight + root.tabsHeight + Style.normalBorderWidth + root.footerHeight
    + root.contentSpacing * 4 + root.listRows * root.rowHeight + (root.listRows - 1) * Style.space(4)
  property int cardHeight: Math.min(card.contentTopInset + card.contentBottomInset + root.contentHeight,
    Style.space(560), panel.height - Style.gapsOut * 2)

  function open(payloadJson) {
    root.opened = true
    root.filterText = ""
    root.searching = false
    root.selectedIndex = 0
    root.cursorActive = true
    root.formMode = ""
    root.pendingConfirm = null
    root.tabIndex = 0
    root.disarmPointer()
    root.refreshAll()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
    root.formMode = ""
    root.pendingConfirm = null
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function") {
      root.shell.hide((root.manifest && root.manifest.id) || "io.github.houtvongsak.herdr-sessions")
    }
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  // ---------------------------------------------------------------- data

  function refreshAll() {
    if (!listProc.running) listProc.running = true
    if (!attachedProc.running) attachedProc.running = true
    if (!machineListProc.running) machineListProc.running = true
  }

  function refreshLocal() {
    if (!listProc.running) listProc.running = true
    if (!attachedProc.running) attachedProc.running = true
  }

  function parseJson(raw, fallback, what) {
    if (!String(raw || "").trim()) return fallback
    try {
      return JSON.parse(raw)
    } catch (e) {
      console.warn("herdr-sessions: couldn't read " + what + ":", e, raw)
      return fallback
    }
  }

  function parseSessions(raw) {
    root.sessions = root.parseJson(raw, {}, "herdr session list").sessions || []
    root.rebuildDisplay()
  }

  // The machine list arrives at once; each machine's sessions follow over SSH.
  function parseMachineList(raw) {
    var data = root.parseJson(raw, {}, "the machine list")
    root.hostName = data.host || root.hostName
    var previous = {}
    for (var i = 0; i < root.machines.length; i++) previous[root.machines[i].key] = root.machines[i]
    root.machines = (data.machines || []).map(function(m) {
      var old = previous[m.key]
      return old ? old : { target: m.target, key: m.key, label: m.target, loaded: false, ok: false, error: "", sessions: [] }
    })
    if (root.tabIndex > root.machines.length) root.tabIndex = root.machines.length
    root.rebuildDisplay()
    if (root.machines.length > 0 && !machinesProc.running) machinesProc.running = true
  }

  function parseMachines(raw) {
    var rows = root.parseJson(raw, [], "remote sessions")
    var byKey = {}
    for (var i = 0; i < rows.length; i++) byKey[rows[i].key] = rows[i]
    root.machines = root.machines.map(function(m) {
      var row = byKey[m.key]
      if (!row) return m
      return { target: row.target, key: row.key, label: row.label, loaded: true, ok: row.ok === true,
        error: row.error || "", sessions: row.sessions || [] }
    })
    root.rebuildDisplay()
  }

  function parseAttached(raw) {
    root.attached = root.parseJson(raw, [], "attached herdr clients")
    root.rebuildDisplay()
  }

  function isAttached(key, name) {
    for (var i = 0; i < root.attached.length; i++) {
      if (root.attached[i].key === key && root.attached[i].session === name) return true
    }
    return false
  }

  function tabAt(index) {
    if (index === 0) {
      return { local: true, key: "", target: "", label: root.hostName || "This computer", loaded: true, ok: true,
        error: "", sessions: root.sessions }
    }
    var m = root.machines[index - 1]
    if (!m) return null
    return { local: false, key: m.key, target: m.target, label: m.label, loaded: m.loaded, ok: m.ok, error: m.error,
      sessions: m.sessions }
  }

  function tabCount() {
    return root.machines.length + 1
  }

  // Session folders on another machine are shown relative to its home, like local ones.
  function prettyPath(path, local) {
    var value = String(path || "")
    if (local && root.home && value.indexOf(root.home) === 0) return "~" + value.slice(root.home.length)
    return value.replace(/^\/home\/[^\/]+/, "~").replace(/^\/root(?=\/|$)/, "~")
  }

  function rebuildDisplay() {
    displayModel.clear()
    var tab = root.currentTab
    var search = root.filterText.trim().toLowerCase()
    var list = tab ? tab.sessions : []

    for (var i = 0; i < list.length; i++) {
      var s = list[i]
      if (search && s.name.toLowerCase().indexOf(search) === -1) continue
      displayModel.append({
        isNewButton: false,
        name: s.name,
        running: s.running === true,
        isDefault: s.default === true,
        sessionDir: root.prettyPath(s.session_dir || "", tab.local),
        attachedHere: root.isAttached(tab.key, s.name)
      })
    }

    if (!search && tab && (tab.local || tab.ok)) {
      displayModel.append({ isNewButton: true, name: "", running: false, isDefault: false, sessionDir: "",
        attachedHere: false })
    }

    if (displayModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0

    Qt.callLater(function() {
      if (displayModel.count > 0) sessionList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  // ---------------------------------------------------------------- navigation

  function select(delta) {
    if (displayModel.count === 0) return
    root.disarmPointer()
    if (!cursorActive) {
      cursorActive = true
      selectedIndex = delta < 0 ? displayModel.count - 1 : 0
    } else {
      selectedIndex = (selectedIndex + delta + displayModel.count) % displayModel.count
    }
    sessionList.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  function switchTab(delta) {
    root.setTab((root.tabIndex + delta + root.tabCount()) % root.tabCount())
  }

  function setTab(index) {
    if (index === root.tabIndex) return
    root.tabIndex = index
    root.selectedIndex = 0
    root.cursorActive = true
    root.disarmPointer()
    root.rebuildDisplay()
  }

  function selectedRow() {
    if (!root.cursorActive || root.selectedIndex < 0 || root.selectedIndex >= displayModel.count) return null
    return displayModel.get(root.selectedIndex)
  }

  function activate(row) {
    if (!row) return
    if (row.isNewButton) root.startForm("session")
    else root.launchSession(root.currentTab, row.name)
  }

  // ---------------------------------------------------------------- actions

  // A stopped session starts again when it is opened: `herdr --session` starts its server,
  // and `--remote` starts the far side's.
  function launchSession(tab, name) {
    if (!tab) return
    root.dismiss()
    var command = ["omarchy-launch-terminal", "herdr"]
    if (!tab.local) command.push("--remote", tab.target)
    if (name !== "default") command.push("--session", name)
    Quickshell.execDetached(command)
  }

  function stopSession(row) {
    var tab = root.currentTab
    if (!row || row.isNewButton || !row.running || !tab) return
    if (!tab.local) {
      Quickshell.execDetached([root.dataScript, "stop", tab.target, row.name])
      remoteRefreshTimer.restart()
      return
    }
    if (row.isDefault) {
      Quickshell.execDetached(["herdr", "server", "stop"])
    } else {
      Quickshell.execDetached(["herdr", "session", "stop", row.name])
    }
    refreshTimer.restart()
  }

  function requestDeleteSession(row) {
    var tab = root.currentTab
    if (!row || row.isNewButton || row.running || row.isDefault || !tab) return
    confirmDialog.selectedIndex = 1
    root.pendingConfirm = { kind: "delete", target: tab.local ? "" : tab.target, name: row.name }
  }

  function requestRemoveMachine() {
    var tab = root.currentTab
    if (!tab || tab.local) return
    confirmDialog.selectedIndex = 1
    root.pendingConfirm = { kind: "remove", target: tab.target, name: tab.label }
  }

  function cancelConfirm() {
    root.pendingConfirm = null
    root.disarmPointer()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function executeConfirm() {
    var pending = root.pendingConfirm
    root.cancelConfirm()
    if (!pending) return
    if (pending.kind === "remove") {
      Quickshell.execDetached([root.dataScript, "remove", pending.target])
      root.tabIndex = 0
      machineListTimer.restart()
    } else if (pending.target) {
      Quickshell.execDetached([root.dataScript, "delete", pending.target, pending.name])
      remoteRefreshTimer.restart()
    } else {
      Quickshell.execDetached(["herdr", "session", "delete", pending.name])
      refreshTimer.restart()
    }
  }

  function startForm(mode) {
    if (mode === "session" && root.currentTab && !root.currentTab.local && !root.currentTab.ok) return
    root.formMode = mode
    formInput.text = ""
    Qt.callLater(function() { formInput.forceActiveFocus() })
  }

  function cancelForm() {
    root.formMode = ""
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function submitForm() {
    var value = formInput.text.trim()
    if (!value) return
    var mode = root.formMode
    root.formMode = ""
    if (mode === "machine") {
      Quickshell.execDetached([root.dataScript, "add", value])
      machineListTimer.restart()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    } else {
      root.launchSession(root.currentTab, value)
    }
  }

  function setFilter(next) {
    root.filterText = next
    root.selectedIndex = 0
    root.cursorActive = true
    root.disarmPointer()
    root.rebuildDisplay()
  }

  function disarmPointer() {
    pointerGate.reset()
  }

  function selectFromPointer(index, item, mouse) {
    if (!pointerGate.moved(item, mouse)) return
    root.cursorActive = true
    root.selectedIndex = index
  }

  function isPrintable(event) {
    return event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127
  }

  ListModel { id: displayModel }

  PointerMoveGate {
    id: pointerGate
    referenceItem: card
  }

  Process {
    id: listProc
    command: ["herdr", "session", "list", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseSessions(text)
    }
  }

  Process {
    id: attachedProc
    command: [root.dataScript, "attached"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseAttached(text)
    }
  }

  Process {
    id: machineListProc
    command: [root.dataScript, "list"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseMachineList(text)
    }
  }

  Process {
    id: machinesProc
    command: [root.dataScript, "machines"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseMachines(text)
    }
  }

  Timer {
    id: refreshTimer
    interval: 350
    repeat: false
    onTriggered: root.refreshLocal()
  }

  Timer {
    id: remoteRefreshTimer
    interval: 1500
    repeat: false
    onTriggered: if (!machinesProc.running) machinesProc.running = true
  }

  Timer {
    id: machineListTimer
    interval: 300
    repeat: false
    onTriggered: if (!machineListProc.running) machineListProc.running = true
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-herdr-sessions"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        z: root.pendingConfirm ? 20 : 0
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (confirmDialog.opened) {
            // h, j, k and l move between the buttons, like the arrow keys.
            var bare = !event.modifiers || event.modifiers === Qt.ShiftModifier
            var vim = [Qt.Key_H, Qt.Key_J, Qt.Key_K, Qt.Key_L].indexOf(event.key) !== -1
            if (bare && vim) confirmDialog.selectedIndex = confirmDialog.selectedIndex === 0 ? 1 : 0
            else if (!confirmDialog.handleKey(event)) return
            event.accepted = true
            return
          }

          var plain = !event.modifiers || event.modifiers === Qt.ShiftModifier
          event.accepted = true

          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else if (root.searching) root.searching = false
            else root.dismiss()
          } else if (event.key === Qt.Key_Up) {
            root.select(-1)
          } else if (event.key === Qt.Key_Down) {
            root.select(1)
          } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Backtab) {
            root.switchTab(-1)
          } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) {
            root.switchTab(1)
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.activate(root.selectedRow())
          } else if (root.searching) {
            // While searching, letters go into the search; arrows and Enter still work.
            if (Util.editsFilter(event, root.filterText)) root.setFilter(Util.editedFilter(event, root.filterText))
            else if (event.key === Qt.Key_Backspace) root.searching = false
            else if (root.isPrintable(event)) root.setFilter(root.filterText + event.text)
            else event.accepted = false
          } else if (event.key === Qt.Key_Slash) {
            root.searching = true
          } else if (event.key === Qt.Key_J && plain) {
            root.select(1)
          } else if (event.key === Qt.Key_K && plain) {
            root.select(-1)
          } else if (event.key === Qt.Key_H && plain) {
            root.switchTab(-1)
          } else if (event.key === Qt.Key_L && plain) {
            root.switchTab(1)
          } else if (event.key === Qt.Key_Delete || (event.key === Qt.Key_D && plain)) {
            root.requestDeleteSession(root.selectedRow())
          } else if (event.key === Qt.Key_S && plain) {
            root.stopSession(root.selectedRow())
          } else if (event.key === Qt.Key_N && plain) {
            root.startForm("session")
          } else if (event.key === Qt.Key_A && plain) {
            root.startForm("machine")
          } else if (event.key === Qt.Key_X && plain) {
            root.requestRemoveMachine()
          } else if (event.key === Qt.Key_R && plain) {
            root.refreshAll()
          } else {
            event.accepted = false
          }
        }

        ConfirmDialog {
          id: confirmDialog
          anchors.fill: parent
          z: 10
          opened: root.pendingConfirm !== null
          message: !root.pendingConfirm ? ""
            : root.pendingConfirm.kind === "remove"
              ? "Stop listing “" + root.pendingConfirm.name + "”? Its sessions keep running."
              : "Delete session “" + root.pendingConfirm.name + "”" + (root.pendingConfirm.target ? " on " + root.currentTab.label : "") + "?"
          confirmText: root.pendingConfirm && root.pendingConfirm.kind === "remove" ? "Remove" : "Delete"
          background: root.background
          foreground: root.foreground
          scrim: root.scrim
          selectedBackground: root.selectedBackground
          selectedText: root.selectedText
          fontFamily: root.fontFamily
          cornerRadius: root.cornerRadius
          onCanceled: root.cancelConfirm()
          onConfirmed: root.executeConfirm()
        }
      }

      Item {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset

        // Header: search text on the left, this tab's session count on the right
        Item {
          id: header
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          height: root.headerHeight

          Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.right: countText.left
            anchors.rightMargin: root.contentSpacing
            anchors.verticalCenter: parent.verticalCenter
            text: root.formMode === "session" ? "New session on " + (root.currentTab ? root.currentTab.label : "")
              : root.formMode === "machine" ? "Add a machine"
              : root.filterText || (root.searching ? "Search…" : "Herdr sessions")
            color: root.foreground
            opacity: root.filterText || root.formMode || !root.searching ? 1 : 0.58
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            elide: Text.ElideRight
          }

          Text {
            id: countText
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            readonly property var tab: root.currentTab
            text: !tab ? "" : !tab.loaded ? "checking…" : !tab.ok ? "unreachable"
              : tab.sessions.length + (tab.sessions.length === 1 ? " session" : " sessions")
            color: root.foreground
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        // One tab per machine, this computer first
        Row {
          id: tabs
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: header.bottom
          anchors.topMargin: root.contentSpacing
          height: root.tabsHeight
          spacing: Style.space(6)
          clip: true

          Repeater {
            model: root.tabCount()

            Rectangle {
              id: tabChip
              required property int index
              readonly property var tab: root.tabAt(index)
              readonly property bool current: index === root.tabIndex

              width: tabLabel.implicitWidth + Style.spacing.controlPaddingX * 2
              height: root.tabsHeight
              radius: root.cornerRadius
              color: current ? root.selectedBackground : "transparent"
              border.width: Style.normalBorderWidth
              border.color: Util.alpha(root.foreground, current ? 0.5 : 0.18)

              Text {
                id: tabLabel
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: tabChip.tab ? tabChip.tab.label + (tabChip.tab.loaded && !tabChip.tab.ok ? " !" : "") : ""
                color: tabChip.current ? root.selectedText : root.foreground
                opacity: tabChip.current ? 1 : (tabChip.tab && tabChip.tab.loaded && !tabChip.tab.ok ? 0.4 : 0.65)
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setTab(tabChip.index)
              }
            }
          }
        }

        Rectangle {
          id: headerRule
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: tabs.bottom
          anchors.topMargin: root.contentSpacing
          height: Style.normalBorderWidth
          color: Util.alpha(root.border, 0.28)
        }

        Item {
          id: content
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: headerRule.bottom
          anchors.topMargin: root.contentSpacing
          anchors.bottom: footer.top
          anchors.bottomMargin: root.contentSpacing

          ListView {
            id: sessionList
            anchors.fill: parent
            visible: root.formMode === ""
            model: displayModel
            clip: true
            spacing: Style.space(4)
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
              id: row
              required property int index
              required property bool isNewButton
              required property string name
              required property bool running
              required property bool isDefault
              required property string sessionDir
              required property bool attachedHere

              readonly property bool hasCursor: root.cursorActive && index === root.selectedIndex
              readonly property color textColor: hasCursor ? root.selectedText : root.foreground
              // Lit when a herdr window on this computer shows the session; dim otherwise.
              readonly property real nameOpacity: isNewButton || attachedHere || hasCursor ? 1 : (running ? 0.62 : 0.42)

              width: ListView.view.width
              height: root.rowHeight
              radius: root.cornerRadius
              color: hasCursor ? root.selectedBackground
                : attachedHere ? Util.alpha(Color.accent, 0.08) : "transparent"

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: function(mouse) { root.selectFromPointer(row.index, row, mouse) }
                onClicked: {
                  root.cursorActive = true
                  root.selectedIndex = row.index
                  root.activate(displayModel.get(row.index))
                }
              }

              // Leading marker column: status dot, or "+" for the new row
              Item {
                id: marker
                anchors.left: parent.left
                anchors.leftMargin: root.rowPadding
                anchors.verticalCenter: parent.verticalCenter
                width: root.markerWidth
                height: parent.height

                Rectangle {
                  visible: !row.isNewButton
                  anchors.centerIn: parent
                  width: Style.space(8)
                  height: width
                  radius: width / 2
                  color: row.running ? Color.accent : "transparent"
                  opacity: row.attachedHere ? 1 : 0.6
                  border.width: row.running ? 0 : Style.normalBorderWidth
                  border.color: Util.alpha(root.foreground, 0.45)
                }

                Text {
                  visible: row.isNewButton
                  anchors.centerIn: parent
                  text: "+"
                  color: row.textColor
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                }
              }

              Column {
                anchors.left: marker.right
                anchors.leftMargin: Style.space(10)
                anchors.right: trailing.left
                anchors.rightMargin: root.contentSpacing
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Row {
                  spacing: Style.space(8)

                  Text {
                    textFormat: Text.PlainText
                    text: row.isNewButton ? "New session" : row.name
                    color: row.textColor
                    opacity: row.nameOpacity
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                    font.bold: row.attachedHere
                  }

                  Text {
                    visible: row.isDefault
                    anchors.verticalCenter: parent.verticalCenter
                    text: "default"
                    color: root.foreground
                    opacity: 0.5
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  text: row.isNewButton
                    ? "Create and open a new herdr session on " + (root.currentTab ? root.currentTab.label : "")
                    : row.sessionDir
                  color: root.foreground
                  opacity: 0.45
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideMiddle
                }
              }

              // Trailing column: actions on the cursor row, status otherwise
              Item {
                id: trailing
                anchors.right: parent.right
                anchors.rightMargin: root.rowPadding
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(statusText.implicitWidth, actions.implicitWidth)
                height: parent.height
                visible: !row.isNewButton

                Text {
                  id: statusText
                  visible: !row.hasCursor
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  text: row.attachedHere ? "open here" : row.running ? "running" : "stopped"
                  color: row.running ? Color.accent : root.foreground
                  opacity: row.attachedHere ? 1 : row.running ? 0.7 : 0.4
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                // Pull icon buttons out by their padding so glyphs line up
                // with the status text edge.
                Row {
                  id: actions
                  visible: row.hasCursor
                  anchors.right: parent.right
                  anchors.rightMargin: -Style.spacing.controlPaddingX
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(2)

                  Button {
                    visible: row.running
                    iconText: ""
                    tooltipText: "Stop (s)"
                    foreground: root.foreground
                    onClicked: root.stopSession(displayModel.get(row.index))
                  }

                  Button {
                    visible: !row.running && !row.isDefault
                    iconText: ""
                    tooltipText: "Delete (d)"
                    foreground: root.foreground
                    onClicked: root.requestDeleteSession(displayModel.get(row.index))
                  }

                  Button {
                    iconText: ""
                    tooltipText: "Open (Enter)"
                    foreground: root.selectedText
                    onClicked: root.activate(displayModel.get(row.index))
                  }
                }
              }
            }
          }

          // Empty tab: still checking, unreachable, or nothing matches the search
          Column {
            anchors.centerIn: parent
            width: parent.width - root.rowPadding * 2
            spacing: Style.space(6)
            visible: root.formMode === "" && displayModel.count === 0

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              textFormat: Text.PlainText
              readonly property var tab: root.currentTab
              text: root.filterText ? "No sessions match “" + root.filterText + "”"
                : !tab ? "" : !tab.loaded ? "Asking " + tab.label + "…"
                : !tab.ok ? "Couldn't reach " + tab.target : "No sessions"
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
            }

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              textFormat: Text.PlainText
              wrapMode: Text.Wrap
              visible: text.length > 0
              text: root.currentTab && root.currentTab.loaded && !root.currentTab.ok && !root.filterText
                ? root.currentTab.error : ""
              color: root.foreground
              opacity: 0.45
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          // New session / add machine form
          Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: root.rowPadding
            anchors.rightMargin: root.rowPadding
            anchors.topMargin: root.rowPadding
            visible: root.formMode !== ""
            spacing: Style.spacing.lg

            Text {
              text: root.formMode === "machine"
                ? "SSH target (user@host or a Host from ~/.ssh/config). It needs SSH without a password prompt, and herdr."
                : "Session name"
              width: parent.width
              wrapMode: Text.Wrap
              color: root.foreground
              opacity: 0.58
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            TextField {
              id: formInput
              width: parent.width
              placeholderText: root.formMode === "machine" ? "e.g. you@buildbox" : "e.g. project-x"
              foreground: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              onAccepted: root.submitForm()
              Keys.onEscapePressed: root.cancelForm()
            }

            Row {
              anchors.right: parent.right
              spacing: Style.space(10)

              Button {
                text: "Cancel"
                bordered: true
                fontFamily: root.fontFamily
                foreground: root.foreground
                onClicked: root.cancelForm()
              }

              Button {
                text: root.formMode === "machine" ? "Add" : "Create"
                bordered: true
                fontFamily: root.fontFamily
                foreground: root.selectedText
                onClicked: root.submitForm()
              }
            }
          }
        }

        // Footer key hints
        Text {
          id: footer
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: root.footerHeight
          verticalAlignment: Text.AlignBottom
          text: root.formMode ? "enter " + (root.formMode === "machine" ? "add" : "create") + " · esc cancel"
            : root.searching ? "type to search · ↑↓ select · enter open · esc stop searching"
            : "h l machine · j k move · enter open · / search · n new · s stop · d delete · a x add/remove machine"
          color: root.foreground
          opacity: 0.45
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }
}
