import 'package:dart_mappable/dart_mappable.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

part 'android_channel.mapper.dart';

const _methodChannel = MethodChannel('org.localsend.localsend_app/localsend');
const _pickerUpdateChannel = MethodChannel('org.localsend.localsend_app/picker');
final _logger = Logger('AndroidSaf');

/// From Android 10 and above, we need to use the Storage Access Framework (SAF) to access files due to the scoped storage.
/// SAF itself is available from Android 4.4 (API level 19).
/// We implemented our own algorithm to build encode and decode content URIs.
/// Older versions might also work but the encoded content URI is not guaranteed to work with our algorithm.
const contentUriMinSdk = 27;

Future<PickDirectoryResult?> pickDirectoryAndroid() async {
  final result = await _methodChannel.invokeMethod<Map>('pickDirectory');
  if (result == null) {
    return null;
  }

  return PickDirectoryResultMapper.fromJson({
    'directoryUri': result['directoryUri'],
    'files': (result['files'] as List).map((e) => FileInfoMapper.fromJson((e as Map).cast<String, dynamic>())).toList(),
  });
}

Future<String?> pickDirectoryPathAndroid() async {
  final result = await _methodChannel.invokeMethod<String>('pickDirectoryPath');
  return result;
}

/// Result of [pickFilesAndroid].
///
/// Android reports the picked files in two phases so that the selection list
/// appears immediately: [files] contains best-effort metadata right away and,
/// when [complete] is false, the final metadata is delivered later via
/// [listenPickerUpdates].
class PickFilesResult {
  final List<FileInfo> files;

  /// Whether [files] already contains the final metadata.
  final bool complete;

  PickFilesResult({
    required this.files,
    required this.complete,
  });
}

/// An update for a file that was picked with [pickFilesAndroid].
///
/// Reading the metadata of a content uri may be slow (the document provider
/// can live in another process), so it is delivered asynchronously.
class PickerFileUpdate {
  /// The content uri of the file, used to identify it in the selection.
  final String uri;
  final String? name;

  /// The size in bytes or null when unknown.
  final int? size;

  /// RFC 3339 in UTC. Null when the document provider does not know it.
  final String? lastModified;

  /// Whether the metadata could not be read at all.
  final bool failed;

  PickerFileUpdate({
    required this.uri,
    required this.name,
    required this.size,
    required this.lastModified,
    required this.failed,
  });
}

Future<PickFilesResult?> pickFilesAndroid() async {
  final result = await _methodChannel.invokeMethod<Map>('pickFiles');
  if (result == null) {
    return null;
  }

  return PickFilesResult(
    files: (result['files'] as List).map((e) => FileInfoMapper.fromJson((e as Map).cast<String, dynamic>())).toList(),
    complete: result['complete'] as bool? ?? true,
  );
}

/// Registers a listener for the asynchronous metadata updates of picked files.
///
/// The listener is replaced on every call, which is fine because updates are
/// identified by the uri of the file they belong to.
void listenPickerUpdates(void Function(PickerFileUpdate update) onUpdate) {
  _pickerUpdateChannel.setMethodCallHandler((call) async {
    if (call.method != 'onFileInfo') {
      return;
    }
    final args = (call.arguments as Map).cast<String, dynamic>();
    onUpdate(
      PickerFileUpdate(
        uri: args['uri'] as String,
        name: args['name'] as String?,
        size: (args['size'] as num?)?.toInt(),
        lastModified: args['lastModified'] as String?,
        failed: args['failed'] as bool? ?? false,
      ),
    );
  });
}

/// Returns the global "Download" directory, e.g. /storage/emulated/0/Download.
Future<String?> getDownloadsDirectoryAndroid() async {
  try {
    return await _methodChannel.invokeMethod<String>('getDownloadsDirectory');
  } catch (e) {
    _logger.warning('Could not get downloads directory', e);
    return null;
  }
}

Future<bool> getSystemAnimationsStatusAndroid() async {
  return await _methodChannel.invokeMethod('isAnimationsEnabled') ?? true;
}

/// Requests the "Nearby devices" permission gating local network access on Android 17+.
/// Returns true when granted or when running on an older Android version.
Future<bool> requestLocalNetworkPermissionAndroid() async {
  try {
    return await _methodChannel.invokeMethod<bool>('requestLocalNetworkPermission') ?? false;
  } catch (e) {
    _logger.warning('Could not request local network permission', e);
    return false;
  }
}

Future<void> openContentUri({
  required String uri,
}) async {
  _logger.info('Opening content URI: $uri');
  await _methodChannel.invokeMethod('openContentUri', {
    'uri': uri,
  });
}

/// Tells MainActivity that the Dart side is now subscribed to the share_handler media stream,
/// so share intents that were held back during app start can be replayed.
Future<void> flushPendingShareIntentsAndroid() async {
  try {
    await _methodChannel.invokeMethod('shareIntentReady');
  } catch (e) {
    _logger.warning('Could not flush pending share intents', e);
  }
}

Future<void> openGallery() async {
  _logger.info('Opening gallery');
  await _methodChannel.invokeMethod('openGallery');
}

@MappableClass()
class PickDirectoryResult with PickDirectoryResultMappable {
  final String directoryUri;
  final List<FileInfo> files;

  PickDirectoryResult({
    required this.directoryUri,
    required this.files,
  });
}

@MappableClass()
class FileInfo with FileInfoMappable {
  final String name;
  final int size;
  final String uri;

  /// RFC 3339 in UTC. Null when the document provider does not know it.
  final String? lastModified;

  FileInfo({
    required this.name,
    required this.size,
    required this.uri,
    required this.lastModified,
  });
}
