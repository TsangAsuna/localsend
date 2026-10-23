import 'dart:io';

import 'package:device_apps/device_apps.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/util/native/channel/android_channel.dart' as android_channel;
import 'package:localsend_isolates/model/file_type.dart';
import 'package:localsend_isolates/rust/api/metadata.dart';
import 'package:localsend_isolates/util/file_path_helper.dart';
import 'package:share_handler/share_handler.dart';
import 'package:uri_content/uri_content.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

final _uriContent = UriContent();

/// Utility functions to convert third party models to common [CrossFile] model.
class CrossFileConverters {
  /// Adds a media asset to the list.
  ///
  /// On Android, the file is never copied out of the media store: it is
  /// streamed directly via its content URI during the transfer (the asset id
  /// is the MediaStore id). Only the (fast) content length is queried, so the
  /// selection list is ready immediately.
  ///
  /// On other platforms (iOS), the system copies the file into the app
  /// sandbox, which is fast.
  static Future<CrossFile> convertAssetEntity(AssetEntity asset) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final mediaType = switch (asset.type) {
        AssetType.video => 'video',
        AssetType.audio => 'audio',
        _ => 'image',
      };
      final uri = Uri.parse('content://media/external/$mediaType/media/${asset.id}');
      final size = await _uriContent.getContentLengthOrNull(uri);
      return CrossFile(
        name: await asset.titleAsync,
        fileType: asset.type == AssetType.video ? FileType.video : FileType.image,
        size: size ?? -1,
        thumbnail: null,
        asset: asset,
        path: uri.toString(),
        bytes: null,
        lastModified: asset.modifiedDateSecond != null && asset.modifiedDateSecond! > 0
            ? DateTime.fromMillisecondsSinceEpoch(asset.modifiedDateSecond! * 1000, isUtc: true).toIso8601String()
            : null,
        lastAccessed: null,
      );
    }

    final file = await asset.originFile;
    if (file == null) {
      return CrossFile(
        name: await asset.titleAsync,
        fileType: asset.type == AssetType.video ? FileType.video : FileType.image,
        size: -1,
        thumbnail: null,
        asset: asset,
        path: null, // loaded in the background
        bytes: null,
        lastModified: null,
        lastAccessed: null,
      );
    }
    final metadata = await readFileMetadata(path: file.path);
    return CrossFile(
      name: await asset.titleAsync,
      fileType: asset.type == AssetType.video ? FileType.video : FileType.image,
      size: await file.length(),
      thumbnail: null,
      asset: asset,
      path: file.path,
      bytes: null,
      lastModified: metadata?.modified,
      lastAccessed: metadata?.accessed,
    );
  }

  /// Copies the actual file of an [asset] out of the media store.
  ///
  /// This is only used as a fallback for assets whose size could not be
  /// determined via the content URI (see [convertAssetEntity]).
  static Future<AssetFileDetails> loadAssetFileDetails(AssetEntity asset) async {
    final file = await asset.originFile;
    if (file == null) {
      return const AssetFileDetails(failed: true);
    }
    final metadata = await readFileMetadata(path: file.path);
    return AssetFileDetails(
      path: file.path,
      size: await file.length(),
      lastModified: metadata?.modified,
    );
  }

  static Future<CrossFile> convertXFile(XFile file) async {
    final metadata = kIsWeb ? null : await readFileMetadata(path: file.path);
    return CrossFile(
      name: file.name,
      fileType: file.name.guessFileType(),
      size: await file.length(),
      thumbnail: null,
      asset: null,
      path: kIsWeb ? null : file.path,
      bytes: kIsWeb ? await file.readAsBytes() : null, // we can fetch it now because in Web it is already there
      lastModified: metadata?.modified,
      lastAccessed: metadata?.accessed,
    );
  }

  static Future<CrossFile> convertFile(File file) async {
    final metadata = await readFileMetadata(path: file.path);
    return CrossFile(
      name: file.path.fileName,
      fileType: file.path.fileName.guessFileType(),
      size: await file.length(),
      thumbnail: null,
      asset: null,
      path: file.path,
      bytes: null,
      lastModified: metadata?.modified,
      lastAccessed: metadata?.accessed,
    );
  }

  static Future<CrossFile> convertFileInfo(android_channel.FileInfo file) async {
    return CrossFile(
      name: file.name,
      fileType: file.name.guessFileType(),
      size: file.size,
      thumbnail: null,
      asset: null,
      path: file.uri,
      bytes: null,
      // SAF only provides milliseconds, so there is no point statting in Rust.
      lastModified: file.lastModified,
      lastAccessed: null,
    );
  }

  static Future<CrossFile> convertSharedAttachment(SharedAttachment attachment) async {
    final file = File(attachment.path);
    final fileName = attachment.path.fileName;
    final metadata = await readFileMetadata(path: file.path);
    return CrossFile(
      name: fileName,
      fileType: fileName.guessFileType(),
      size: await file.length(),
      thumbnail: null,
      asset: null,
      path: file.path,
      bytes: null,
      lastModified: metadata?.modified,
      lastAccessed: metadata?.accessed,
    );
  }

  static Future<CrossFile> convertApplication(Application app) async {
    final file = File(app.apkFilePath);
    return CrossFile(
      name: '${app.appName.trim()} - v${app.versionName}.apk',
      fileType: FileType.apk,
      thumbnail: app is ApplicationWithIcon ? app.icon : null,
      size: await file.length(),
      asset: null,
      path: app.apkFilePath,
      bytes: null,
      lastModified: null,
      lastAccessed: null,
    );
  }
}

/// The loaded file details of a media asset.
class AssetFileDetails {
  final String path;
  final int size;

  /// RFC 3339 in UTC.
  final String? lastModified;

  /// Whether the file could not be loaded at all.
  final bool failed;

  const AssetFileDetails({
    this.path = '',
    this.size = -1,
    this.lastModified,
    this.failed = false,
  });
}

extension CompareFile on CrossFile {
  bool isSameFile({required CrossFile otherFile}) {
    if (asset != null && otherFile.asset != null) {
      // Media assets are identified by their asset id because the path is
      // only available after the file has been loaded in the background.
      return asset!.id == otherFile.asset!.id;
    }
    return (path ?? '') == (otherFile.path ?? '');
  }
}
