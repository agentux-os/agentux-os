
// ---- AgentUX live session only (appended by live/build.sh) -----------------
// A note on the desktop that explains the live session and the demo. Its text
// is ~/.local/share/plasma_notes/agentux-live, put there at boot by livesys.
{
    const liveDesktop = desktopsForActivity(currentActivity())[0];
    if (liveDesktop) {
        const liveGeo = screenGeometry(liveDesktop.screen);
        const noteWidth = Math.round(gridUnit * 24);
        const noteHeight = Math.round(gridUnit * 21);
        const note = liveDesktop.addWidget("org.kde.plasma.notes",
            liveGeo.width - noteWidth - gridUnit * 2, gridUnit * 2, noteWidth, noteHeight);
        note.currentConfigGroup = ["General"];
        note.writeConfig("noteId", "agentux-live");
        note.writeConfig("color", "black");
    }
}
