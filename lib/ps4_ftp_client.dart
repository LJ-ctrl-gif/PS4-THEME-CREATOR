import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Passive-mode FTP transport for a PS4 FTP server on the local network.
class Ps4FtpClient {
  Ps4FtpClient(this.host, this.port, this.username, this.password);

  final String host;
  final int port;
  final String username;
  final String password;
  Socket? _control;
  StreamIterator<String>? _lines;

  Future<String> _readReply() async {
    final lines = _lines;
    if (lines == null) throw StateError('FTP connection is closed.');
    if (!await lines.moveNext().timeout(const Duration(seconds: 15))) {
      throw const SocketException('No reply from PS4 FTP server.');
    }
    final first = lines.current;
    if (first.length < 3) return first;
    final code = first.substring(0, 3);
    if (first.length > 3 && first[3] == '-') {
      while (await lines.moveNext().timeout(const Duration(seconds: 15))) {
        final line = lines.current;
        if (line.startsWith('$code ')) return line;
      }
    }
    return first;
  }

  Future<String> _command(String command) async {
    final socket = _control;
    if (socket == null) throw StateError('FTP connection is closed.');
    socket.write('$command\r\n');
    await socket.flush();
    return _readReply();
  }

  Future<void> connect() async {
    _control = await Socket.connect(host, port, timeout: const Duration(seconds: 8));
    _lines = StreamIterator<String>(
      utf8.decoder.bind(_control!).transform(const LineSplitter()),
    );
    final greeting = await _readReply();
    if (!greeting.startsWith('220')) {
      throw SocketException('PS4 FTP server rejected connection: $greeting');
    }
    final userReply = await _command('USER $username');
    if (userReply.startsWith('331')) {
      final passReply = await _command('PASS $password');
      if (!passReply.startsWith('230')) throw SocketException('FTP login failed: $passReply');
    } else if (!userReply.startsWith('230')) {
      throw SocketException('FTP login failed: $userReply');
    }
    final typeReply = await _command('TYPE I');
    if (!typeReply.startsWith('200')) throw SocketException('Binary mode failed: $typeReply');
  }

  Future<Socket> _openPassiveDataSocket() async {
    final epsv = await _command('EPSV');
    final extended = RegExp(r'\(\|\|\|(\d+)\|\)').firstMatch(epsv);
    if (epsv.startsWith('229') && extended != null) {
      return Socket.connect(host, int.parse(extended.group(1)!), timeout: const Duration(seconds: 8));
    }
    final pasv = await _command('PASV');
    final values = RegExp(r'\((\d+,\d+,\d+,\d+),(\d+),(\d+)\)').firstMatch(pasv);
    if (!pasv.startsWith('227') || values == null) {
      throw SocketException('Passive mode unavailable: $pasv');
    }
    final dataPort = int.parse(values.group(2)!) * 256 + int.parse(values.group(3)!);
    return Socket.connect(host, dataPort, timeout: const Duration(seconds: 8));
  }

  Future<void> prepareFolder(String folder) async {
    final made = await _command('MKD $folder');
    if (!made.startsWith('257') && !made.startsWith('250') && !made.startsWith('550')) {
      throw SocketException('Could not create destination folder: $made');
    }
    final changed = await _command('CWD $folder');
    if (!changed.startsWith('250')) throw SocketException('Cannot open destination folder: $changed');
  }

  Future<void> uploadFile(File file, String remoteName) async {
    final data = await _openPassiveDataSocket();
    final reply = await _command('STOR $remoteName');
    if (!reply.startsWith('125') && !reply.startsWith('150')) {
      data.destroy();
      throw SocketException('PS4 refused upload for $remoteName: $reply');
    }
    try {
      await file.openRead().pipe(data).timeout(const Duration(minutes: 5));
    } finally {
      data.destroy();
    }
    final finished = await _readReply();
    if (!finished.startsWith('226') && !finished.startsWith('250')) {
      throw SocketException('Upload did not finish: $finished');
    }
  }

  Future<void> close() async {
    try {
      await _command('QUIT');
    } catch (_) {}
    await _lines?.cancel();
    _control?.destroy();
    _control = null;
  }
}
