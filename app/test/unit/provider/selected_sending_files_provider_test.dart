import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/util/native/channel/android_channel.dart' as android_channel;
import 'package:localsend_isolates/model/file_type.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:test/test.dart';

CrossFile _file({
  String name = 'a.txt',
  int size = 123,
  String? path,
}) {
  return CrossFile(
    name: name,
    fileType: name.guessFileType(),
    size: size,
    thumbnail: null,
    asset: null,
    path: path,
    bytes: null,
    lastModified: null,
    lastAccessed: null,
  );
}

android_channel.PickerFileUpdate _update({
  required String uri,
  String? name,
  int? size,
  bool failed = false,
}) {
  return android_channel.PickerFileUpdate(
    uri: uri,
    name: name,
    size: size,
    lastModified: null,
    failed: failed,
  );
}

void main() {
  test('UpdateFileMetadataAction updates the file and resolves pending metadata', () async {
    final service = ReduxNotifier.test(
      redux: SelectedSendingFilesNotifier(),
      initialState: [
        _file(path: 'content://test/1', size: -1),
      ],
    );

    expect(service.notifier.hasPendingMetadata, isTrue);

    final pending = service.notifier.waitForPendingMetadata();

    service.dispatch(
      UpdateFileMetadataAction(
        _update(uri: 'content://test/1', name: 'image.jpg', size: 456),
      ),
    );

    await pending;

    expect(service.notifier.hasPendingMetadata, isFalse);
    expect(service.state.single.name, 'image.jpg');
    expect(service.state.single.size, 456);
    expect(service.state.single.fileType, FileType.image);
  });

  test('UpdateFileMetadataAction ignores unknown uris', () {
    final service = ReduxNotifier.test(
      redux: SelectedSendingFilesNotifier(),
      initialState: [
        _file(path: 'content://test/1', size: 123),
      ],
    );

    service.dispatch(
      UpdateFileMetadataAction(
        _update(uri: 'content://test/unknown', name: 'other.jpg', size: 456),
      ),
    );

    expect(service.state.single.name, 'a.txt');
    expect(service.state.single.size, 123);
  });

  test('UpdateFileMetadataAction removes the file when reading failed', () {
    final service = ReduxNotifier.test(
      redux: SelectedSendingFilesNotifier(),
      initialState: [
        _file(path: 'content://test/1', size: -1),
        _file(name: 'b.txt', path: 'content://test/2', size: 1),
      ],
    );

    service.dispatch(
      UpdateFileMetadataAction(
        _update(uri: 'content://test/1', failed: true),
      ),
    );

    expect(service.state.map((file) => file.name), ['b.txt']);
    expect(service.notifier.hasPendingMetadata, isFalse);
  });

  test('resolveFiles returns the updated files after the metadata has been loaded', () async {
    final service = ReduxNotifier.test(
      redux: SelectedSendingFilesNotifier(),
      initialState: [
        _file(path: 'content://test/1', size: -1),
      ],
    );

    final pending = service.notifier.resolveFiles([service.state.first]);

    service.dispatch(
      UpdateFileMetadataAction(
        _update(uri: 'content://test/1', name: 'image.jpg', size: 456),
      ),
    );

    final resolved = await pending;
    expect(resolved.single.name, 'image.jpg');
    expect(resolved.single.size, 456);
  });

  test('resolveFiles returns the files immediately when nothing is pending', () async {
    final service = ReduxNotifier.test(
      redux: SelectedSendingFilesNotifier(),
      initialState: [
        _file(path: 'content://test/1', size: 123),
      ],
    );

    final resolved = await service.notifier.resolveFiles([service.state.first]);
    expect(resolved.single.size, 123);
  });

  test('pendingAwareTotalSize shows an ellipsis while metadata is pending', () {
    final pending = [_file(path: 'content://test/1', size: -1)];
    final complete = [_file(size: 100), _file(size: 234)];

    expect(pending.pendingAwareTotalSize, '…');
    expect(complete.pendingAwareTotalSize, '334 B');
  });
}
