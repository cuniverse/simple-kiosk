import 'dart:async';

import 'package:flutter/material.dart';

import '../model/idle_config.dart';
import 'idle_overlay.dart';

/// 외부 버튼 등에서 대기화면 진입을 요청하기 위한 컨트롤러.
class IdleGateController {
  VoidCallback? _enterIdle;

  /// 연결된 [IdleGate]를 즉시 대기화면으로 전환한다.
  void enterIdle() => _enterIdle?.call();

  void _attach(VoidCallback enterIdle) => _enterIdle = enterIdle;

  void _detach(VoidCallback enterIdle) {
    if (_enterIdle == enterIdle) _enterIdle = null;
  }
}

/// 대기화면(Idle) 진입/종료를 관리하는 게이트 위젯.
///
/// 동작:
/// - [child] 는 항상 그대로 빌드된다(WebView 재생성 방지).
/// - 사용자의 포인터 입력이 [IdleConfig.timeoutSec] 이상 없으면 대기화면을 띄운다.
/// - [IdleConfig.startOnLaunch] 가 `true` 이면 첫 빌드부터 대기화면을 띄운다.
/// - 대기화면 종료 시 [onWake] 가 호출된다(예: 메뉴를 홈으로 리셋).
class IdleGate extends StatefulWidget {
  final IdleConfig config;
  final Widget child;
  final IdleGateController? controller;

  /// 대기화면이 시작될 때 호출(예: WebView를 홈으로 리셋해두면 잠금화면이 풀릴 때
  /// 깔끔하게 홈에서 시작).
  final VoidCallback? onEnterIdle;

  /// 대기화면이 종료될 때(사용자가 화면을 깨울 때) 호출.
  final VoidCallback? onWake;

  const IdleGate({
    super.key,
    required this.config,
    required this.child,
    this.controller,
    this.onEnterIdle,
    this.onWake,
  });

  @override
  State<IdleGate> createState() => _IdleGateState();
}

class _IdleGateState extends State<IdleGate> {
  late bool _idle;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // 시작 화면보호기는 첫 프레임 뒤에 전환하지 않고 최초 프레임부터 표시한다.
    // Windows 네이티브 WebView가 생성되는 도중 화면보호기 진입 콜백이 WebView를
    // 교체하면 플랫폼 뷰 초기화가 dispose 된 State를 참조할 수 있다.
    _idle = widget.config.isUsable && widget.config.startOnLaunch;
    widget.controller?._attach(_enterIdle);
    if (_idle) {
      // 부모의 세션 정리 작업만 첫 프레임 뒤에 알린다. 화면보호기 자체는 이미
      // 표시 중이므로 _enterIdle()로 다시 상태를 바꾸지 않는다.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_idle) return;
        widget.onEnterIdle?.call();
      });
    } else {
      _resetTimer();
    }
  }

  @override
  void didUpdateWidget(covariant IdleGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach(_enterIdle);
      widget.controller?._attach(_enterIdle);
    }
    if (oldWidget.config.timeoutSec != widget.config.timeoutSec ||
        oldWidget.config.enabled != widget.config.enabled) {
      _resetTimer();
    }
  }

  @override
  void dispose() {
    widget.controller?._detach(_enterIdle);
    _timer?.cancel();
    super.dispose();
  }

  void _enterIdle() {
    if (!widget.config.isUsable) return;
    _timer?.cancel();
    if (!_idle) {
      setState(() => _idle = true);
      widget.onEnterIdle?.call();
    }
  }

  void _wake() {
    if (!_idle) {
      _resetTimer();
      return;
    }
    setState(() => _idle = false);
    widget.onWake?.call();
    _resetTimer();
  }

  void _resetTimer() {
    _timer?.cancel();
    if (!widget.config.isUsable) return;
    final sec = widget.config.timeoutSec;
    if (sec <= 0) return; // 무입력 진입 비활성.
    _timer = Timer(Duration(seconds: sec), () {
      if (!mounted) return;
      _enterIdle();
    });
  }

  /// 사용자의 포인터 입력이 있을 때 호출. 대기화면이 떠 있지 않을 때만 타이머 리셋.
  void _onUserActivity() {
    if (_idle) return;
    _resetTimer();
  }

  @override
  Widget build(BuildContext context) {
    // 입력 가로채기: 자식 위에 투명 Listener를 깔되, 이벤트는 자식에게 그대로 전달.
    final activityDetector = Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _onUserActivity(),
      onPointerMove: (_) => _onUserActivity(),
      onPointerSignal: (_) => _onUserActivity(),
      child: widget.child,
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        activityDetector,
        if (_idle && widget.config.isUsable)
          Positioned.fill(
            child: IdleOverlay(
              config: widget.config,
              onDismiss: _wake,
            ),
          ),
      ],
    );
  }
}
