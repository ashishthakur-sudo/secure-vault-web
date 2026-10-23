import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

const _maxArchiveEntries = 1000;
const _maxExpandedArchiveSize = 16 * 1024 * 1024;
const _maxDocumentXmlSize = 8 * 1024 * 1024;
const _maxPreviewTextLength = 1024 * 1024;

String extractDocxText(Uint8List bytes) {
  var entryCount = 0;
  final archive = ZipDecoder().decodeBytes(
    bytes,
    callback: (_) {
      entryCount++;
      if (entryCount > _maxArchiveEntries) {
        throw const FormatException('This DOCX contains too many files.');
      }
    },
  );

  var expandedSize = 0;
  for (final entry in archive.files) {
    expandedSize += entry.size;
    if (expandedSize > _maxExpandedArchiveSize) {
      throw const FormatException('This DOCX is too large to preview.');
    }
  }

  final document = archive.find('word/document.xml');
  if (document == null || !document.isFile) {
    throw const FormatException(
      'This DOCX does not contain a readable document.',
    );
  }
  if (document.size > _maxDocumentXmlSize) {
    throw const FormatException('This DOCX document is too large to preview.');
  }

  final xmlBytes = document.readBytes();
  if (xmlBytes == null) {
    throw const FormatException('The DOCX document could not be read.');
  }

  final xml = XmlDocument.parse(utf8.decode(xmlBytes));
  final paragraphs = xml
      .findAllElements('p', namespaceUri: '*')
      .map(
        (paragraph) => paragraph
            .findAllElements('t', namespaceUri: '*')
            .map((text) => text.innerText)
            .join(),
      )
      .where((paragraph) => paragraph.trim().isNotEmpty);
  final text = paragraphs.join('\n\n').trim();
  if (text.length > _maxPreviewTextLength) {
    throw const FormatException('The DOCX text is too long to preview.');
  }
  return text.isEmpty ? 'No readable text was found in this document.' : text;
}
