// ignore_for_file: constant_identifier_names

/// Fallback name used when a remote filename cannot be made safe.
const String FALLBACK_FILENAME = 'unknown_file';

/// Maximum accepted length of a sanitized filename.
const int MAX_FILENAME_LENGTH = 200;

/// Returns a safe local filename for a name received from the network.
///
/// Keeps only the last path segment (splitting on both `/` and `\`), removes
/// control characters and falls back to [FALLBACK_FILENAME] when nothing usable
/// is left (empty, `.` or `..`).
String sanitizeFilename(String? remoteName) {
  if (remoteName == null) return FALLBACK_FILENAME;

  final lastSegment = remoteName.split(RegExp(r'[\\/]')).last;
  final cleaned = lastSegment.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim();

  if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') return FALLBACK_FILENAME;
  if (cleaned.length <= MAX_FILENAME_LENGTH) return cleaned;
  return cleaned.substring(0, MAX_FILENAME_LENGTH);
}
