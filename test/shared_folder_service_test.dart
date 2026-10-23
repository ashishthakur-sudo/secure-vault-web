import 'package:flutter_test/flutter_test.dart';
import 'package:secure_vault/src/shared/shared_folder_service.dart';

void main() {
  test('shared files identify in-app preview formats by extension', () {
    expect(_sharedFile('photo.PNG').previewCategory, 'Images');
    expect(_sharedFile('report.pdf').previewCategory, 'PDFs');
    expect(_sharedFile('report.docx').previewCategory, 'DOCX');
    expect(_sharedFile('clip.mp4').previewCategory, 'Videos');
    expect(_sharedFile('song.wav').previewCategory, 'Audios');
    expect(_sharedFile('notes.md').previewCategory, 'Text');
    expect(_sharedFile('archive.zip').previewCategory, isNull);
  });
}

SharedFile _sharedFile(String name) => SharedFile(
  id: '00000000-0000-0000-0000-000000000001',
  name: name,
  contentType: 'application/octet-stream',
  size: 1,
  createdAt: DateTime.utc(2025),
);
