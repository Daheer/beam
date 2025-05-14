import 'package:flutter/material.dart';
import '../services/agora_service.dart';
import '../services/call_service.dart';
import '../services/config.dart';

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

  @override
  void initState() {
    super.initState();
    _initializeCall();
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
      setState(() {
        _remoteUsers.add(uid);
        _isCallConnected = true;
      });
      // Update call status when remote user joins
      _callService.updateCallStatus(widget.channelName, CallStatus.connected);
    });

    _agoraService.onRemoteUserLeft.listen((uid) {
      setState(() {
        _remoteUsers.remove(uid);
        _isCallConnected = false;
      });
      // End call when remote user leaves
      _onCallEnd();
    });
    print('joining channel: ${widget.channelName}');

    if (widget.isIncoming) {
      // Update call status to ringing for incoming calls
      await _callService.updateCallStatus(
        widget.channelName,
        CallStatus.ringing,
      );
    }
    // Join the channel
    await _agoraService.joinChannel(widget.channelName, AppConfig.agoraToken);
  }

  @override
  void dispose() {
    _agoraService.dispose();
    super.dispose();
  }

  void _onToggleMute() {
    setState(() {
      _isMuted = !_isMuted;
      _agoraService.toggleMicrophone(!_isMuted);
    });
  }

  void _onCallEnd() async {
    await _callService.endCall(widget.channelName);
    await _agoraService.leaveChannel();
    if (mounted) {
      Navigator.pop(context);
    }
  }

  void _onRejectCall() async {
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
        _onCallEnd();
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.isIncoming ? 'Incoming Call' : 'Outgoing Call'),
          centerTitle: true,
          automaticallyImplyLeading: false,
        ),
        body: Stack(
          children: [
            // Call status and participants
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _isCallConnected ? Icons.phone_in_talk : Icons.phone,
                    size: 88,
                    color: _isCallConnected ? Colors.green : Colors.blue,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    _isCallConnected
                        ? 'Call Connected'
                        : widget.isIncoming
                        ? 'Incoming Call...'
                        : 'Calling...',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _remoteUsers.isEmpty
                        ? 'Waiting for connection...'
                        : 'Call in progress',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
            // Call controls
            Positioned(
              left: 0,
              right: 0,
              bottom: 48,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isCallConnected) ...[
                    // Mute button
                    RawMaterialButton(
                      onPressed: _onToggleMute,
                      elevation: 2.0,
                      fillColor: _isMuted ? Colors.red : Colors.white,
                      padding: const EdgeInsets.all(12.0),
                      shape: const CircleBorder(),
                      child: Icon(
                        _isMuted ? Icons.mic_off : Icons.mic,
                        color: _isMuted ? Colors.white : Colors.black,
                        size: 24.0,
                      ),
                    ),
                    const SizedBox(width: 24),
                  ],
                  // End/Reject call button
                  RawMaterialButton(
                    onPressed:
                        widget.isIncoming && !_isCallConnected
                            ? _onRejectCall
                            : _onCallEnd,
                    elevation: 2.0,
                    fillColor: Colors.red,
                    padding: const EdgeInsets.all(15.0),
                    shape: const CircleBorder(),
                    child: Icon(
                      widget.isIncoming && !_isCallConnected
                          ? Icons.call_end
                          : Icons.call_end,
                      color: Colors.white,
                      size: 32.0,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
