import 'dart:typed_data';

class FileDropListener {
  final Function(Uint8List bytes, String fileName) onFileDropped;
  final Function(bool isDraggingOver)? onDragStateChanged;

  FileDropListener({
    required this.onFileDropped,
    this.onDragStateChanged,
  });

  void dispose() {}
}
