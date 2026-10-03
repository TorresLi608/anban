import 'dart:convert';
import 'dart:typed_data';

const maxAttachmentBytes = 200 * 1024 * 1024;
const attachmentChunkBytes = 4 * 1024 * 1024;

Stream<Uint8List> attachmentChunks(Stream<List<int>> source) async* {
  var pending = BytesBuilder(copy: false);
  await for (final bytes in source) {
    var offset = 0;
    while (offset < bytes.length) {
      final count = (attachmentChunkBytes - pending.length).clamp(
        0,
        bytes.length - offset,
      );
      pending.add(Uint8List.fromList(bytes.sublist(offset, offset + count)));
      offset += count;
      if (pending.length == attachmentChunkBytes) {
        yield pending.takeBytes();
        pending = BytesBuilder(copy: false);
      }
    }
  }
  if (pending.isNotEmpty) yield pending.takeBytes();
}

class RemoteAttachment {
  final List<String> parts;
  final int? size;
  final String? salt;
  RemoteAttachment(this.parts, {this.size, this.salt});
  bool get legacy => salt == null;
  dynamic toJson() =>
      legacy ? parts.single : {'chunks': parts, 'size': size, 'salt': salt};
  factory RemoteAttachment.fromJson(dynamic value) {
    final RemoteAttachment file;
    if (value is String) {
      file = RemoteAttachment([value]);
    } else if (value is Map &&
        value['chunks'] is List &&
        value['size'] is int &&
        value['salt'] is String) {
      file = RemoteAttachment(
        List<String>.from(value['chunks']),
        size: value['size'],
        salt: value['salt'],
      );
      if (file.size! < 1 ||
          file.size! > maxAttachmentBytes ||
          base64Decode(file.salt!).length != 16 ||
          file.parts.length !=
              (file.size! + attachmentChunkBytes - 1) ~/ attachmentChunkBytes) {
        throw const FormatException('远端附件信息无效');
      }
    } else {
      throw const FormatException('远端附件信息无效');
    }
    if (file.parts.isEmpty ||
        file.parts.any((id) => !RegExp(r'^[a-f0-9]{64}$').hasMatch(id))) {
      throw const FormatException('远端附件标识无效');
    }
    return file;
  }
}
