import 'dart:async';
import 'dart:typed_data';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

class FileDropListener {
  final Function(Uint8List bytes, String fileName) onFileDropped;
  final Function(bool isDraggingOver)? onDragStateChanged;

  StreamSubscription? _dragOverSub;
  StreamSubscription? _dragEnterSub;
  StreamSubscription? _dragLeaveSub;
  StreamSubscription? _dropSub;
  int _dragCounter = 0;

  FileDropListener({
    required this.onFileDropped,
    this.onDragStateChanged,
  }) {
    _start();
  }

  void _start() {
    _dragEnterSub = html.document.onDragEnter.listen((event) {
      event.preventDefault();
      _dragCounter++;
      if (_dragCounter == 1) {
        onDragStateChanged?.call(true);
      }
    });

    _dragOverSub = html.document.onDragOver.listen((event) {
      event.preventDefault();
      event.dataTransfer.dropEffect = 'copy';
    });

    _dragLeaveSub = html.document.onDragLeave.listen((event) {
      _dragCounter--;
      if (_dragCounter <= 0) {
        _dragCounter = 0;
        onDragStateChanged?.call(false);
      }
    });

    _dropSub = html.document.onDrop.listen((event) {
      event.preventDefault();
      _dragCounter = 0;
      onDragStateChanged?.call(false);

      final files = event.dataTransfer.files;
      if (files != null && files.isNotEmpty) {
        final file = files[0];
        final name = file.name.toLowerCase();
        if (name.endsWith('.jpg') ||
            name.endsWith('.jpeg') ||
            name.endsWith('.png') ||
            name.endsWith('.webp')) {
          final reader = html.FileReader();
          reader.readAsArrayBuffer(file);
          reader.onLoadEnd.listen((_) {
            if (reader.result != null) {
              final bytes = Uint8List.fromList(reader.result as List<int>);
              onFileDropped(bytes, file.name);
            }
          });
        }
      }
    });
  }

  void dispose() {
    _dragEnterSub?.cancel();
    _dragOverSub?.cancel();
    _dragLeaveSub?.cancel();
    _dropSub?.cancel();
  }
}
