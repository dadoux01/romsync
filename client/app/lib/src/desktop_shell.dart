import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nativeapi/nativeapi.dart' as native;
import 'package:tray_manager/tray_manager.dart' show ImageAsset;

import 'app_controller.dart';
import 'l10n.dart';

/// System tray icon, window closing to the tray, and desktop notifications,
/// through nativeapi (Linux: StatusNotifierItem over D-Bus, no AppIndicator
/// library needed; macOS: menu bar; Windows: notification area).
class DesktopShell {
  DesktopShell(this.controller);

  final AppController controller;
  native.TrayIcon? _tray;
  native.Window? _window;
  var _quitting = false;
  var _nativeNotifications = false;
  Locale? _menuLocale;

  /// Sets up the tray; throws when the desktop has no tray.
  Future<void> init() async {
    if (!native.TrayManager.instance.isSupported()) {
      throw UnsupportedError('no system tray on this desktop');
    }
    _window = native.WindowManager.instance.getCurrent();
    _window?.addListener((event) {
      // Closing the window keeps RomSync in the tray, watching the saves of
      // games launched without it, unless the user disabled it.
      if (event is native.WindowCloseRequestedEvent && !_quitting && controller.config.keepInTray) {
        event.request.cancel();
        _window?.hide();
      }
    });

    final tray = native.TrayIcon.create() ?? (throw UnsupportedError('cannot create the tray icon'));
    tray.icon = ImageAsset.fromAsset(
      Platform.isWindows
          ? 'assets/tray/tray.ico'
          : Platform.isMacOS
          ? 'assets/tray/tray_template.png'
          : 'assets/tray/tray.png',
    );
    tray.isIconTemplate = Platform.isMacOS;
    tray.setTooltip('RomSync');

    _tray = tray;
    _buildMenu();
    // The menu follows a change of language in the settings.
    controller.addListener(() {
      if (controller.locale != _menuLocale) _buildMenu();
    });
    // Linux panels open the exported menu themselves; elsewhere a right click.
    tray.setContextMenuTrigger(native.ContextMenuTrigger.rightClicked);
    tray.addListener((e) {
      if (e is native.TrayIconClickedEvent) show();
    });
    tray.setVisible(true);

    final notifications = native.NotificationManager.instance;
    _nativeNotifications = notifications.isSupported() && notifications.initialize();
    controller.onNotice = (title, body) => unawaited(_notify(title, body));
    controller.quitApp = () async => quit();
    if (_nativeNotifications) {
      // A click on a notification opens RomSync, and the dialog of a
      // divergence waiting for a choice.
      notifications.addListener((e) {
        if (e is native.NotificationActivatedEvent) {
          show();
          controller.openPendingDivergence();
        }
      });
    }
  }

  /// The tray menu, in the language of the interface.
  void _buildMenu() {
    _menuLocale = controller.locale;
    final l = textsFor(_menuLocale!);
    final menu = native.Menu.create()!;
    void item(String label, void Function() onClick) {
      final i = native.MenuItem.createWithLabelAndType(label, native.MenuItemType.normal)!;
      i.addListener((e) {
        if (e is native.MenuItemClickedEvent) onClick();
      });
      menu.addItem(i);
    }

    item(l.trayOpen, show);
    item(l.traySyncNow, () => unawaited(controller.rescan()));
    menu.addSeparator();
    item(l.trayQuit, quit);
    _tray?.setContextMenu(menu);
  }

  Future<void> _notify(String title, String body) async {
    try {
      if (_nativeNotifications && native.NotificationManager.instance.show(title, body, 'romsync', '')) return;
      // Fallbacks without any extra library.
      if (Platform.isLinux) {
        await Process.run('gdbus', [
          'call', '--session', '--dest', 'org.freedesktop.Notifications', //
          '--object-path', '/org/freedesktop/Notifications',
          '--method', 'org.freedesktop.Notifications.Notify',
          'RomSync', '0', 'romsync', title, body, '[]', '{}', '8000',
        ]);
      } else if (Platform.isMacOS) {
        String q(String s) => s.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
        await Process.run('osascript', ['-e', 'display notification "${q(body)}" with title "${q(title)}"']);
      }
    } catch (e) {
      debugPrint('notification failed: $e');
    }
  }

  void show() {
    _window?.show();
    _window?.focus();
  }

  void quit() {
    _quitting = true;
    _tray?.setVisible(false);
    native.Application.instance.quit(0);
  }
}
