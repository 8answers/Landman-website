import 'dart:typed_data';

Object? preOpenPrintWindow() {
  return null;
}

void closePrintWindow(Object? windowHandle) {}

Future<void> printReportImages(
  List<Uint8List> pageImages, {
  Object? preOpenedWindow,
}) async {
  throw UnsupportedError(
      'System print dialog is not available on this platform.');
}
