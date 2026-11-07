# romsync_core

Platform-independent logic of the RomSync client, in pure Dart so that it can
be tested without Flutter (`dart test`): API client, NDS header reading and game
identifiers, conversion profiles, local state, upload queue, sync engine and
emulator profiles. The Flutter app in `../../app` is only a user interface on
top of it.
