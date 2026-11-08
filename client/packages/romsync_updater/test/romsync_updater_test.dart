import 'dart:io';

import 'package:romsync_updater/romsync_updater.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late String target;

  String read(String dir) => File('$dir/version.txt').readAsStringSync();
  void install(String dir, String version) {
    Directory(dir).createSync(recursive: true);
    File('$dir/version.txt').writeAsStringSync(version);
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('romsync-updater-');
    target = '${tmp.path}/RomSync';
    install(target, '0.5.0');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('the new version takes the place of the old one, kept until cleanup', () async {
    install(stagingPath(target), '0.5.1');
    await swapInstall(target: target, staged: stagingPath(target));
    expect(read(target), '0.5.1');
    expect(read(backupPath(target)), '0.5.0');
    expect(Directory(stagingPath(target)).existsSync(), isFalse);

    await cleanupAfterUpdate(target);
    expect(Directory(backupPath(target)).existsSync(), isFalse);
    expect(read(target), '0.5.1');
  });

  test('a leftover backup of an earlier update is replaced', () async {
    install(backupPath(target), '0.4.0');
    install(stagingPath(target), '0.5.1');
    await swapInstall(target: target, staged: stagingPath(target));
    expect(read(backupPath(target)), '0.5.0');
  });

  test('a missing new version changes nothing', () async {
    await expectLater(swapInstall(target: target, staged: stagingPath(target)), throwsA(isA<UpdateInstallException>()));
    expect(read(target), '0.5.0');
  });

  test('when the new version cannot be put in place, the old one is restored', () async {
    install(stagingPath(target), '0.5.1');
    var calls = 0;
    Future<void> failingSecond(String from, String to) async {
      calls++;
      if (from == stagingPath(target)) throw FileSystemException('locked', from);
      await Directory(from).rename(to);
    }

    await expectLater(
      swapInstall(
        target: target,
        staged: stagingPath(target),
        attempts: 3,
        delay: Duration.zero,
        rename: failingSecond,
      ),
      throwsA(isA<UpdateInstallException>().having((e) => e.message, 'message', contains('remise en place'))),
    );
    expect(read(target), '0.5.0');
    expect(Directory(backupPath(target)).existsSync(), isFalse);
    expect(calls, 1 + 3 + 1, reason: 'move away, 3 attempts, move back');
  });

  test('when the installation cannot be moved away, nothing changes', () async {
    install(stagingPath(target), '0.5.1');
    Future<void> locked(String from, String to) async => throw FileSystemException('in use', from);
    await expectLater(
      swapInstall(target: target, staged: stagingPath(target), attempts: 2, delay: Duration.zero, rename: locked),
      throwsA(isA<UpdateInstallException>().having((e) => e.message, 'message', contains('Rien n’a changé'))),
    );
    expect(read(target), '0.5.0');
    expect(read(stagingPath(target)), '0.5.1');
  });

  test('waits for a process to exit', () async {
    final proc = await Process.start(Platform.isWindows ? 'timeout' : 'sleep', Platform.isWindows ? ['1'] : ['1']);
    expect(await processRuns(proc.pid), isTrue);
    expect(await waitForExit(proc.pid, timeout: const Duration(seconds: 10)), isTrue);
    expect(await processRuns(proc.pid), isFalse);
  }, testOn: '!windows');

  test('installTarget and launchPath per system', () {
    expect(installTarget(executable: '/opt/romsync/romsync', os: 'linux'), '/opt/romsync');
    expect(
      installTarget(executable: '/Applications/RomSync.app/Contents/MacOS/RomSync', os: 'macos'),
      '/Applications/RomSync.app',
    );
    expect(installTarget(executable: r'C:\Jeux\RomSync\romsync.exe', os: 'windows'), r'C:\Jeux\RomSync');
    expect(launchPath(os: 'macos'), 'Contents/MacOS/RomSync');
  });

  test('stages a release archive next to the installation', () async {
    final src = Directory('${tmp.path}/src/romsync-0.5.1-linux-x64')..createSync(recursive: true);
    File('${src.path}/romsync').writeAsStringSync('new');
    final archive = File('${tmp.path}/romsync-0.5.1-linux-x64.tar.gz');
    final r = await Process.run('tar', ['-czf', archive.path, '-C', '${tmp.path}/src', 'romsync-0.5.1-linux-x64']);
    expect(r.exitCode, 0);

    expect(await canReplace(target), isTrue);
    final staged = await stageRelease(archive: archive, target: target, launch: 'romsync');
    expect(staged, stagingPath(target));
    expect(File('$staged/romsync').readAsStringSync(), 'new');
    expect(Directory('$target.extract').existsSync(), isFalse);

    await expectLater(
      stageRelease(archive: archive, target: target, launch: 'missing'),
      throwsA(isA<UpdateInstallException>()),
    );
    expect(Directory(stagingPath(target)).existsSync(), isFalse);
  }, testOn: 'linux || mac-os');
}
