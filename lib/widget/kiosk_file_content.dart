import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../model/menu_file_target.dart';
import '../service/video_controller_factory.dart';
import 'file_image_stub.dart' if (dart.library.io) 'file_image_io.dart' as fi;
import 'kiosk_webview.dart' show WebZoomControls;

/// `item.file`을 확장자에 따라 이미지 또는 동영상으로 표시한다.
/// 로컬 페이지는 [KioskWebView]가 담당한다.
class KioskFileContent extends StatefulWidget {
  final String file;
  final bool active;
  final Brightness webViewBrightness;
  final Color? backgroundColor;
  final VoidCallback? onInitialLoadReady;

  const KioskFileContent({
    super.key,
    required this.file,
    required this.active,
    this.webViewBrightness = Brightness.light,
    this.backgroundColor,
    this.onInitialLoadReady,
  });

  @override
  State<KioskFileContent> createState() => _KioskFileContentState();
}

class _KioskFileContentState extends State<KioskFileContent> {
  VideoPlayerController? _videoController;
  String? _error;
  bool _readyReported = false;
  final TransformationController _imageTransformation =
      TransformationController();
  double _imageScale = 1;
  static const double _minImageScale = 0.5;
  static const double _maxImageScale = 3;
  static const double _imageZoomStep = 0.25;

  MenuFileKind get _kind => MenuFileTarget.classify(widget.file);
  bool get _isAsset => MenuFileTarget.isAsset(widget.file);
  String get _path => _isAsset
      ? MenuFileTarget.assetPath(widget.file)
      : MenuFileTarget.fileSystemPath(widget.file);

  @override
  void initState() {
    super.initState();
    if (_kind == MenuFileKind.video) {
      unawaited(_initializeVideo());
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reportReady());
    }
  }

  @override
  void didUpdateWidget(covariant KioskFileContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file != widget.file) {
      _disposeVideo();
      _error = null;
      _readyReported = false;
      _setImageScale(1);
      if (_kind == MenuFileKind.video) {
        unawaited(_initializeVideo());
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) => _reportReady());
      }
      return;
    }
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) return;
    if (widget.active && !oldWidget.active) {
      unawaited(controller.play());
    } else if (!widget.active && oldWidget.active) {
      unawaited(controller.pause());
    }
  }

  void _reportReady() {
    if (!mounted || _readyReported) return;
    _readyReported = true;
    widget.onInitialLoadReady?.call();
  }

  Future<void> _initializeVideo() async {
    final controller = _isAsset
        ? VideoControllerFactory.asset(_path)
        : VideoControllerFactory.file(_path);
    _videoController = controller;
    try {
      await controller.initialize();
      if (!mounted || !identical(controller, _videoController)) {
        await controller.dispose();
        return;
      }
      await controller.setLooping(true);
      if (widget.active) await controller.play();
      setState(() {});
    } catch (error) {
      if (!mounted || !identical(controller, _videoController)) return;
      setState(() => _error = '동영상을 재생할 수 없습니다.\n$_path\n$error');
    } finally {
      if (identical(controller, _videoController)) _reportReady();
    }
  }

  void _disposeVideo() {
    final controller = _videoController;
    _videoController = null;
    if (controller != null) unawaited(controller.dispose());
  }

  @override
  void dispose() {
    _disposeVideo();
    _imageTransformation.dispose();
    super.dispose();
  }

  Color get _imageBackgroundColor =>
      widget.backgroundColor ??
      (widget.webViewBrightness == Brightness.dark
          ? const Color(0xFF121212)
          : Colors.white);

  void _setImageScale(double requestedScale) {
    final target = requestedScale.clamp(_minImageScale, _maxImageScale);
    _imageTransformation.value = Matrix4.diagonal3Values(target, target, 1);
    if (mounted && (_imageScale - target).abs() > 0.005) {
      setState(() => _imageScale = target);
    } else {
      _imageScale = target;
    }
  }

  void _onImageInteractionUpdate(ScaleUpdateDetails _) {
    final scale = _imageTransformation.value.getMaxScaleOnAxis().clamp(
          _minImageScale,
          _maxImageScale,
        );
    if ((_imageScale - scale).abs() <= 0.005) return;
    setState(() => _imageScale = scale);
  }

  Widget _errorView(String message, {Color color = Colors.black}) => ColoredBox(
        color: color,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color.computeLuminance() > 0.5
                    ? Colors.black
                    : Colors.white,
                fontSize: 20,
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_error case final error?) return _errorView(error);
    if (_kind == MenuFileKind.image) {
      final backgroundColor = _imageBackgroundColor;
      Widget errorBuilder(BuildContext _, Object __, StackTrace? ___) =>
          _errorView(
            '이미지를 표시할 수 없습니다.\n$_path',
            color: backgroundColor,
          );
      return ColoredBox(
        color: backgroundColor,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                transformationController: _imageTransformation,
                minScale: _minImageScale,
                maxScale: _maxImageScale,
                onInteractionUpdate: _onImageInteractionUpdate,
                child: SizedBox.expand(
                  child: _isAsset
                      ? Image.asset(
                          _path,
                          fit: BoxFit.contain,
                          errorBuilder: errorBuilder,
                        )
                      : fi.buildFileImage(
                          _path,
                          BoxFit.contain,
                          errorBuilder,
                        ),
                ),
              ),
            ),
            if ((_imageScale - 1).abs() > 0.01)
              Positioned(
                top: 12,
                left: 12,
                child: SafeArea(
                  child: WebZoomControls(
                    scale: _imageScale,
                    canZoomOut: _imageScale > _minImageScale + 0.01,
                    canZoomIn: _imageScale < _maxImageScale - 0.01,
                    onZoomOut: () =>
                        _setImageScale(_imageScale - _imageZoomStep),
                    onZoomIn: () =>
                        _setImageScale(_imageScale + _imageZoomStep),
                    onReset: () => _setImageScale(1),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator(color: Colors.white70)),
      );
    }
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }
}
