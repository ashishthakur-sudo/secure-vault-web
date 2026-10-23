import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_vault/src/viewer/docx_text_extractor.dart';

void main() {
  test('extracts text from DOCX paragraphs and runs', () {
    final archive = Archive()
      ..addFile(
        ArchiveFile.string('word/document.xml', '''
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p><w:r><w:t>Hello </w:t></w:r><w:r><w:t>world</w:t></w:r></w:p>
    <w:p><w:r><w:t>Second paragraph</w:t></w:r></w:p>
  </w:body>
</w:document>
'''),
      );

    final bytes = Uint8List.fromList(ZipEncoder().encodeBytes(archive));
    expect(extractDocxText(bytes), 'Hello world\n\nSecond paragraph');
  });

  test('rejects files that are not DOCX archives', () {
    expect(
      () => extractDocxText(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
  });
}
