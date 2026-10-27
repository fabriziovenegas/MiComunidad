import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/services/private_file_service.dart';

void main() {
  const bucket = 'demo-private-files.appspot.com';
  for (final path in [
    'projects/p/photos/upload_photo.png',
    'reports/r/photos/report_photo.jpg',
    'events/e/photos/photo.webp',
    'events/e/minutes/minutes.pdf',
    'access_requests/anonymous/identity/document.pdf',
  ]) {
    test('authenticated reference and legacy URL both resolve only to $path',
        () {
      expect(PrivateFileService.objectPath('gs://$bucket/$path', bucket), path);
      expect(
          PrivateFileService.objectPath(
              'https://firebasestorage.googleapis.com/v0/b/$bucket/o/${Uri.encodeComponent(path)}?alt=media&token=fictional-old-token',
              bucket),
          path);
    });
  }
  for (final url in [
    'https://example.com/poison.pdf',
    'javascript:alert(1)',
    'file:///private/document.pdf',
    'gs://another-bucket/events/e/minutes/a.pdf',
    'gs://$bucket/events/e/minutes/../a.pdf',
    'gs://$bucket/events/e/minutes/%2E%2E',
    'https://firebasestorage.googleapis.com.evil.example/v0/b/$bucket/o/a',
    'https://firebasestorage.googleapis.com/v0/b/another-bucket/o/events%2Fe%2Fminutes%2Fa.pdf',
    'https://firebasestorage.googleapis.com/v0/b/$bucket/o/users%2Fprivate',
    'https://attacker@firebasestorage.googleapis.com/v0/b/$bucket/o/events%2Fe%2Fminutes%2Fa.pdf',
    'https://firebasestorage.googleapis.com:444/v0/b/$bucket/o/events%2Fe%2Fminutes%2Fa.pdf',
    'gs://$bucket/unknown/e/photos/a.png',
    'gs://$bucket/projects/p/minutes/a.pdf',
  ]) {
    test('external, wrong-bucket or unexpected reference is blocked: $url', () {
      expect(() => PrivateFileService.objectPath(url, bucket),
          throwsFormatException);
    });
  }
}
