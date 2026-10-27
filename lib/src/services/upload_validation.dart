const maximumUploadSizeBytes = 20 * 1024 * 1024;
const allowedUploadExtensions = <String>{'pdf', 'png', 'jpg', 'mp4', 'mp3'};

String validateUploadFile(String name, int size) {
  final fileName = name.trim();
  if (fileName.isEmpty ||
      fileName.length > 255 ||
      fileName.contains('/') ||
      fileName.contains(r'\') ||
      RegExp(r'[\u0000-\u001f\u007f]').hasMatch(fileName)) {
    throw const FormatException('Invalid file name.');
  }

  final dot = fileName.lastIndexOf('.');
  final extension = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  if (!allowedUploadExtensions.contains(extension)) {
    throw const FormatException(
      'Only PDF, PNG, JPG, MP4, and MP3 files are allowed.',
    );
  }
  if (size < 0 || size > maximumUploadSizeBytes) {
    throw const FormatException('Files must be 20 MB or smaller.');
  }
  return extension;
}

void validateUploadContents(String name, List<int> bytes) {
  final extension = validateUploadFile(name, bytes.length);
  final validSignature = switch (extension) {
    'pdf' => _startsWith(bytes, const [0x25, 0x50, 0x44, 0x46, 0x2d]),
    'png' => _startsWith(bytes, const [
      0x89,
      0x50,
      0x4e,
      0x47,
      0x0d,
      0x0a,
      0x1a,
      0x0a,
    ]),
    'jpg' => _startsWith(bytes, const [0xff, 0xd8, 0xff]),
    'mp4' =>
      bytes.length >= 12 &&
          bytes[4] == 0x66 &&
          bytes[5] == 0x74 &&
          bytes[6] == 0x79 &&
          bytes[7] == 0x70,
    'mp3' =>
      _startsWith(bytes, const [0x49, 0x44, 0x33]) ||
          (bytes.length >= 2 && bytes[0] == 0xff && bytes[1] & 0xe0 == 0xe0),
    _ => false,
  };
  if (!validSignature) {
    throw const FormatException(
      'The file contents do not match the selected file type.',
    );
  }
}

bool _startsWith(List<int> bytes, List<int> prefix) =>
    bytes.length >= prefix.length &&
    prefix.asMap().entries.every((entry) => bytes[entry.key] == entry.value);
