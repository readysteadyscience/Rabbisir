# Privacy and local data

Rabbisir runs its compatible runtime as an App-owned local child process and communicates through a private loopback endpoint. User-facing diagnostics do not expose the endpoint or port.

DeepSeek credentials use the runtime's write-only credential path. Rabbisir does not display, print, export, or copy stored secret values. Session Log export contains the runtime's real session archive and requires an explicit user action.

The native conversation model admits only approved user-visible data. System messages, developer instructions, hidden context, credentials, raw tool payloads, and unknown projection nodes do not enter the visible model or message clipboard actions.

Project removal changes Rabbisir's project list only. It does not delete the corresponding local folder. Conversation history is stored by the runtime and is not hidden inside the selected project directory.

Rabbisir does not control external browser applications. The current browser status indicator remains inactive until an App-owned embedded controller exists.
