import 'package:flutter_test/flutter_test.dart';
import 'package:secure_vault/src/services/upload_validation.dart';

void main() {
  test('accepts only the configured upload extensions', () {
    for (final name in [
      'document.pdf',
      'image.png',
      'image.jpg',
      'clip.mp4',
      'song.mp3',
    ]) {
      expect(() => validateUploadFile(name, 1), returnsNormally);
    }
    expect(() => validateUploadFile('image.jpeg', 1), throwsFormatException);
    expect(
      () => validateUploadFile('folder/image.png', 1),
      throwsFormatException,
    );
  });

  test('rejects files larger than 20 MiB', () {
    expect(
      () => validateUploadFile('document.pdf', maximumUploadSizeBytes + 1),
      throwsFormatException,
    );
  });

  test('rejects bytes that do not match the file extension', () {
    expect(
      () => validateUploadContents('image.png', [0, 1, 2]),
      throwsFormatException,
    );
    expect(
      () => validateUploadContents('image.png', [
        0x89,
        0x50,
        0x4e,
        0x47,
        0x0d,
        0x0a,
        0x1a,
        0x0a,
      ]),
      returnsNormally,
    );
  });
}
