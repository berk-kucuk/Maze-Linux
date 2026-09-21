/*
 * Maze OLED — desktop layout applied when the Global Theme is selected WITH
 * "Use desktop layout from theme". Without this file Plasma falls back to its
 * stock layout (wiping the Maze panel), which is what made selecting the theme
 * look like it "reset KDE to stock". Only CORE Plasma 6 widgets are used here so
 * applying the layout can never fail on a missing third-party plasmoid.
 *
 * The richer shipped panel (system monitors, netspeed, thermal, etc.) lives in
 * the user's plasma-org.kde.plasma.desktop-appletsrc; this is the safe, always-
 * valid reconstruction of the Maze top panel + bottom dock.
 */

// Every screen gets a desktop with the Maze active-blur wallpaper. a2n.blur is
// bundled per-user in ~/.local/share/plasma/wallpapers (shipped in /etc/skel),
// so it always resolves; if it were ever missing Plasma simply shows no
// wallpaper (it never aborts the layout the way a missing applet would).
for (var i = 0; i < screenCount; ++i) {
    var desktop = new Activity;
    desktop.name = "Maze";
    desktop.wallpaperPlugin = "a2n.blur";
    desktop.currentConfigGroup = ["Wallpaper", "a2n.blur", "General"];
    desktop.writeConfig("Image", "file:///usr/share/wallpapers/Maze/");
    desktop.writeConfig("ActiveBlur", true);
    desktop.writeConfig("BlurRadius", 50);
    desktop.writeConfig("AnimationDuration", 250);
    desktop.writeConfig("SlidePaths", "/usr/share/wallpapers/");
}

// --- Top panel: launcher, clock and a system tray -------------------------
var top = new Panel;
top.location = "top";
top.height = Math.round(gridUnit * 1.6);

var kickoff = top.addWidget("org.kde.plasma.kickoff");
kickoff.currentConfigGroup = ["General"];
kickoff.writeConfig("icon", "/usr/share/pixmaps/maze-simple-logo.png");

top.addWidget("org.kde.plasma.panelspacer");
var clock = top.addWidget("org.kde.plasma.digitalclock");
top.addWidget("org.kde.plasma.panelspacer");
top.addWidget("org.kde.plasma.systemtray");

// --- Bottom dock: window task bar ----------------------------------------
var dock = new Panel;
dock.location = "bottom";
dock.height = Math.round(gridUnit * 2.6);
dock.addWidget("org.kde.plasma.icontasks");
