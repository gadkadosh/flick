## UI and app verification

- Prefer a prepared Tart VM for UI and app-behavior verification. Run the app and all UI interactions inside the guest, then retrieve and inspect the evidence. Tart being installed is not enough: the VM must have a logged-in desktop, remote command access, and the required permissions. If it is unavailable, report this before using the host desktop. Coordinate host reviews first, including checks that require physical displays or hardware.
