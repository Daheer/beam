import 'package:flutter/material.dart';
import '../services/agora_service.dart';
import '../services/call_service.dart';
import '../services/config.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/snackbar_service.dart';

class VoiceCallPage extends StatefulWidget {
  final String channelName;
  final bool isIncoming;
  final String remoteUserId;

  const VoiceCallPage({
    Key? key,
    required this.channelName,
    required this.isIncoming,
    required this.remoteUserId,
  }) : super(key: key);

  @override
  State<VoiceCallPage> createState() => _VoiceCallPageState();
}

class _VoiceCallPageState extends State<VoiceCallPage> {
  final _agoraService = AgoraService();
  final _callService = CallService();
  bool _isMuted = false;
  Set<int> _remoteUsers = {};
  bool _isCallConnected = false;
  Timer? _callTimeoutTimer;
  Timer? _callDurationTimer;
  Duration _callDuration = Duration.zero;
  String _remoteUserName = '';
  String _remoteProfession = '';
  static const int callTimeoutSeconds = 15; // Timeout after 15 seconds

  @override
  void initState() {
    super.initState();
    _initializeCall();
    _loadRemoteUserInfo();
  }

  Future<void> _loadRemoteUserInfo() async {
    try {
      final userDoc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(widget.remoteUserId)
              .get();

      if (userDoc.exists && mounted) {
        final userData = userDoc.data()!;
        setState(() {
          _remoteUserName = userData['name'] ?? 'Unknown User';
          _remoteProfession = userData['profession'] ?? '';
        });
      }
    } catch (e) {
      debugPrint('Error loading remote user info: $e');
    }
  }

  void _startCallDurationTimer() {
    _callDurationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _callDuration += const Duration(seconds: 1);
        });
      }
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String hours =
        duration.inHours > 0 ? '${twoDigits(duration.inHours)}:' : '';
    String minutes = twoDigits(duration.inMinutes.remainder(60));
    String seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$hours$minutes:$seconds';
  }

  Future<void> _initializeCall() async {
    // Request permissions
    final permissionGranted = await _agoraService.requestPermissions();
    if (!permissionGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Microphone permission is required for voice calls'),
          ),
        );
        Navigator.pop(context);
      }
      return;
    }

    // Initialize Agora service
    await _agoraService.initialize();

    // Listen for remote users
    _agoraService.onRemoteUserJoined.listen((uid) {
      if (_callTimeoutTimer != null) {
        _callTimeoutTimer!.cancel();
        _callTimeoutTimer = null;
      }
      if (mounted) {
        setState(() {
          _remoteUsers.add(uid);
          _isCallConnected = true;
        });
        _startCallDurationTimer();
      }
      // Update call status when remote user joins
      _callService.updateCallStatus(widget.channelName, CallStatus.connected);
    });

    _agoraService.onRemoteUserLeft.listen((uid) {
      if (mounted) {
        setState(() {
          _remoteUsers.remove(uid);
          _isCallConnected = false;
        });
      }
      // End call when remote user leaves
      _onCallEnd(reason: 'Remote user ended the call');
    });

    print('joining channel: ${widget.channelName}');

    if (widget.isIncoming) {
      // Update call status to ringing for incoming calls
      await _callService.updateCallStatus(
        widget.channelName,
        CallStatus.ringing,
      );
    } else {
      // Start timeout timer for outgoing calls
      _startCallTimeout();
    }

    // Join the channel with uid=0 to let Agora generate a random UID
    await _agoraService.joinChannel(widget.channelName);
  }

  void _startCallTimeout() {
    _callTimeoutTimer = Timer(Duration(seconds: callTimeoutSeconds), () {
      if (!_isCallConnected && mounted) {
        _onCallEnd(reason: 'No answer - call timed out');
      }
    });
  }

  @override
  void dispose() {
    _callTimeoutTimer?.cancel();
    _callDurationTimer?.cancel();
    _agoraService.dispose();
    super.dispose();
  }

  void _onToggleMute() {
    setState(() {
      _isMuted = !_isMuted;
      _agoraService.toggleMicrophone(!_isMuted);
    });
  }

  void _onCallEnd({String? reason}) async {
    _callTimeoutTimer?.cancel();
    _callDurationTimer?.cancel();
    await _callService.endCall(widget.channelName);
    await _agoraService.leaveChannel();
    if (mounted) {
      if (reason != null) {
        SnackbarService.showWarning(context, message: reason);
      }
      Navigator.pop(context);
    }
  }

  void _onRejectCall() async {
    _callTimeoutTimer?.cancel();
    _callDurationTimer?.cancel();
    await _callService.updateCallStatus(
      widget.channelName,
      CallStatus.rejected,
    );
    await _agoraService.leaveChannel();
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        _onCallEnd(reason: 'Call ended');
        return true;
      },
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Theme.of(context).colorScheme.surface,
                Theme.of(context).colorScheme.surface.withOpacity(0.95),
              ],
            ),
          ),
          child: SafeArea(
            child: Stack(
              children: [
                // Call information
                Positioned.fill(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Profile picture or avatar
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Theme.of(
                            context,
                          ).colorScheme.primaryContainer.withOpacity(0.3),
                        ),
                        child: Icon(
                          _isCallConnected ? Icons.phone_in_talk : Icons.phone,
                          size: 50,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 32),
                      // Remote user name
                      Text(
                        _remoteUserName,
                        style: Theme.of(
                          context,
                        ).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Remote profession
                      Text(
                        _remoteProfession,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Call status
                      Text(
                        _isCallConnected
                            ? 'Connected'
                            : widget.isIncoming
                            ? 'Incoming Call...'
                            : 'Calling...',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color:
                              _isCallConnected
                                  ? Colors.green.shade400
                                  : Theme.of(context).colorScheme.secondary,
                        ),
                      ),
                      if (_isCallConnected) ...[
                        const SizedBox(height: 8),
                        // Call duration
                        Text(
                          _formatDuration(_callDuration),
                          style: Theme.of(
                            context,
                          ).textTheme.titleMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontFeatures: [const FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Top bar with minimal info
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceVariant,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isMuted ? Icons.mic_off : Icons.mic,
                              size: 16,
                              color:
                                  Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _isMuted ? 'Muted' : 'On Call',
                              style: TextStyle(
                                color:
                                    Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Call controls at bottom
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 48,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isCallConnected) ...[
                        // Mute button
                        _CallButton(
                          onPressed: _onToggleMute,
                          icon: _isMuted ? Icons.mic_off : Icons.mic,
                          backgroundColor:
                              _isMuted
                                  ? Theme.of(context).colorScheme.errorContainer
                                  : Theme.of(
                                    context,
                                  ).colorScheme.surfaceVariant,
                          iconColor:
                              _isMuted
                                  ? Theme.of(
                                    context,
                                  ).colorScheme.onErrorContainer
                                  : Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 24),
                      ],
                      // End/Reject call button
                      _CallButton(
                        onPressed:
                            widget.isIncoming && !_isCallConnected
                                ? _onRejectCall
                                : () => _onCallEnd(reason: 'Call ended'),
                        icon: Icons.call_end,
                        backgroundColor: Theme.of(context).colorScheme.error,
                        iconColor: Theme.of(context).colorScheme.onError,
                        size: 65,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final Color backgroundColor;
  final Color iconColor;
  final double size;

  const _CallButton({
    required this.onPressed,
    required this.icon,
    required this.backgroundColor,
    required this.iconColor,
    this.size = 55,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Material(
        shape: const CircleBorder(),
        color: backgroundColor,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: Icon(icon, color: iconColor, size: size * 0.5),
        ),
      ),
    );
  }
}
