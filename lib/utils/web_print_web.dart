import 'dart:html' as html;
import 'dart:typed_data';

html.DivElement? _activePrintRoot;
html.StyleElement? _activePrintStyle;
List<String> _activeBlobUrls = <String>[];

Object? preOpenPrintWindow() {
  return null;
}

void closePrintWindow(Object? windowHandle) {}

Future<void> printReportImages(
  List<Uint8List> pageImages, {
  Object? preOpenedWindow,
}) async {
  if (pageImages.isEmpty) {
    throw StateError('No report pages available for print.');
  }

  _cleanupStalePrintDom();
  _cleanupActivePrintArtifacts();

  final body = html.document.body;
  if (body == null) {
    throw StateError('Unable to access document body for print.');
  }

  final styleElement = html.StyleElement()
    ..setAttribute('data-report-print-style', 'true')
    ..text = '''
@page {
  size: A4 portrait;
  margin: 0;
}

#report-print-root {
  display: block;
  position: fixed;
  left: -200vw;
  top: 0;
  visibility: hidden;
}

@media print {
  html, body {
    position: static !important;
    overflow: visible !important;
    height: auto !important;
    width: auto !important;
    max-height: none !important;
    max-width: none !important;
    margin: 0 !important;
    padding: 0 !important;
    transform: none !important;
  }

  body > *:not(#report-print-root):not(style[data-report-print-style]) {
    display: none !important;
  }

  #report-print-root {
    display: block !important;
    position: static !important;
    left: auto !important;
    top: auto !important;
    visibility: visible !important;
    margin: 0 !important;
    padding: 0 !important;
    background: #fff !important;
  }

  #report-print-root .report-page {
    display: block !important;
    box-sizing: border-box !important;
    width: 210mm !important;
    height: 297mm !important;
    min-height: 297mm !important;
    overflow: hidden !important;
    page-break-after: always !important;
    break-after: page !important;
    page-break-inside: avoid !important;
    break-inside: avoid !important;
  }

  #report-print-root .report-page:last-child {
    page-break-after: auto !important;
    break-after: auto !important;
  }

  #report-print-root .report-page img {
    display: block !important;
    width: 100% !important;
    height: 100% !important;
    object-fit: fill !important;
  }
}
''';

  final printRoot = html.DivElement()..id = 'report-print-root';
  final blobUrls = <String>[];
  final images = <html.ImageElement>[];

  for (final bytes in pageImages) {
    final blob = html.Blob([bytes], 'image/png');
    final blobUrl = html.Url.createObjectUrlFromBlob(blob);
    blobUrls.add(blobUrl);

    final image = html.ImageElement()
      ..src = blobUrl
      ..alt = 'Report page';
    images.add(image);

    final page = html.Element.section()..classes.add('report-page');
    page.append(image);
    printRoot.append(page);
  }

  html.document.head?.append(styleElement);
  body.append(printRoot);
  _activePrintStyle = styleElement;
  _activePrintRoot = printRoot;
  _activeBlobUrls = blobUrls;

  var printTriggered = false;
  try {
    for (var i = 0; i < 80; i++) {
      final allDecoded = images
          .every((img) => (img.complete == true) && (img.naturalWidth > 0));
      if (allDecoded) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    await Future<void>.delayed(const Duration(milliseconds: 900));
    html.window.print();
    printTriggered = true;
  } finally {
    if (!printTriggered) {
      _cleanupActivePrintArtifacts();
    }
  }
}

void _cleanupStalePrintDom() {
  final staleRoots = html.document.querySelectorAll('#report-print-root');
  for (final root in staleRoots) {
    root.remove();
  }

  final staleStyles =
      html.document.querySelectorAll('style[data-report-print-style]');
  for (final style in staleStyles) {
    style.remove();
  }
}

void _cleanupActivePrintArtifacts() {
  _activePrintRoot?.remove();
  _activePrintStyle?.remove();
  for (final url in _activeBlobUrls) {
    html.Url.revokeObjectUrl(url);
  }
  _activePrintRoot = null;
  _activePrintStyle = null;
  _activeBlobUrls = <String>[];
}
