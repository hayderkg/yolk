# Privacy

Yolk has no analytics, advertising, account, cloud sync or automatic crash reporting. It does not send the process list to an external server.

It inspects process names, PIDs, start times, listening ports, executable paths, command-line arguments and working directories exposed by macOS to your user. Command lines are shortened for display, values of flags that look like secrets and credentials inside URLs are masked, and none of it is stored. It may read a nearby `package.json` to name a project and common local icon files to identify it. App icons come from installed application bundles.

When a visible row looks like a web service, icon loading may request `/favicon.ico`, the server's index page and same-origin icon URLs on loopback. Loading is size/time bounded and cached in memory, sends no cookies or stored credentials, and rejects external-origin redirects. Those requests may appear in your local server's logs. A fetch already in progress may finish after the panel closes.

When a container engine's proxy process is listening, Yolk queries the engine over its local Unix socket (Docker Desktop, OrbStack, Colima or Rancher Desktop) for the names, images and published ports of running containers. Stopping a container row sends a stop request over the same socket. Nothing leaves your Mac.

Preferences, the optional global shortcut, favorite and hidden-service keys are stored locally in UserDefaults. These keys may contain project or executable paths. They persist after the associated process exits. Icons and scan results are otherwise held in memory.

Browser and project-folder actions explicitly open the selected address or folder through macOS, in the browser, Finder, editor or terminal you pick. Copying an address writes it to the clipboard. Optional launch at login registers this app with the native macOS service and can be disabled in the same settings panel or System Settings. No launch-at-login registration or notification permission is requested by default.

Public screenshots use sample services. Before sharing your own screenshot, check for private names, paths and addresses.
