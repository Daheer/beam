import 'dart:async';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:beam/services/log_service.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'agora_token_service.dart';

class AgoraService {
  static final AgoraService _singleton = AgoraService._internal();
  factory AgoraService() => _singleton;
  AgoraService._internal();

  RtcEngine? _engine;
  int? _remoteUid;
  bool _isInitialized = false;
  final _onRemoteUserJoinedController = StreamController<int>.broadcast();
  final _onRemoteUserLeftController = StreamController<int>.broadcast();

  Stream<int> get onRemoteUserJoined => _onRemoteUserJoinedController.stream;
  Stream<int> get onRemoteUserLeft => _onRemoteUserLeftController.stream;

  // Initialize the Agora engine
  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    try {
      // Load environment variables
      await dotenv.load();
      final appId = dotenv.env['AGORA_APP_ID'];
      if (appId == null) {
        throw Exception('AGORA_APP_ID not found in environment variables');
      }

      // Create and initialize the engine
      _engine = createAgoraRtcEngine();
      await _engine?.initialize(
        RtcEngineContext(
          appId: appId,
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );

      // Enable audio
      await _engine?.enableAudio();
      await _engine?.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
      await _engine?.setAudioProfile(
        profile: AudioProfileType.audioProfileMusicHighQuality,
        scenario: AudioScenarioType.audioScenarioChatroom,
      );

      // Set up event handlers
      _setupEventHandlers();
      _isInitialized = true;
    } catch (e) {
      await dispose(); // Clean up on error
      rethrow;
    }
  }

  // Clean up resources
  Future<void> dispose() async {
    try {
      if (_engine != null) {
        await leaveChannel();
        await _engine!.release();
        _engine = null;
      }
      _isInitialized = false;
      _remoteUid = null;
    } catch (e) {
      LogService.e('Error disposing Agora service', e, StackTrace.current);
    }
  }

  // Set up event handlers for the Agora engine
  void _setupEventHandlers() {
    _engine?.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          LogService.i("Local user ${connection.localUid} joined");
        },
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          LogService.i("Remote user $remoteUid joined");
          _remoteUid = remoteUid;
          _onRemoteUserJoinedController.add(remoteUid);
        },
        onUserOffline: (
          RtcConnection connection,
          int remoteUid,
          UserOfflineReasonType reason,
        ) {
          _remoteUid = null;
          _onRemoteUserLeftController.add(remoteUid);
        },
        onError: (ErrorCodeType err, String msg) {
          LogService.e("Agora error: $err - $msg", StackTrace.current);
        },
        onConnectionStateChanged: (
          RtcConnection connection,
          ConnectionStateType state,
          ConnectionChangedReasonType reason,
        ) {
          LogService.i("Connection state changed: $state, reason: $reason");
        },
        onTokenPrivilegeWillExpire: (RtcConnection connection, String token) {
          LogService.i("Token will expire soon");
          // Handle token refresh here if needed
        },
      ),
    );
  }

  // Request necessary permissions
  Future<bool> requestPermissions() async {
    final status = await Permission.microphone.request();
    LogService.i('Microphone permission status: $status');
    return status.isGranted;
  }

  // Join a voice channel
  Future<void> joinChannel(String channelName, {int uid = 0}) async {
    if (!_isInitialized || _engine == null) {
      throw Exception('Agora Engine not initialized');
    }

    try {
      // Get a token if not provided
      final channelToken = await AgoraTokenService.generateToken(
        channelName,
        uid.toString(),
      );

      if (channelToken == null) {
        throw Exception('Failed to generate Agora token');
      }

      // Ensure channel name is valid for Agora
      if (channelName.isEmpty) {
        throw Exception('Channel name cannot be empty');
      }

      await _engine?.joinChannel(
        token: channelToken,
        channelId: channelName,
        uid: uid, // If 0, SDK will generate a random UID
        options: const ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          channelProfile: ChannelProfileType.channelProfileCommunication,
          publishMicrophoneTrack: true,
          autoSubscribeAudio: true,
        ),
      );
    } catch (e) {
      LogService.e('Error joining channel', e, StackTrace.current);
      rethrow;
    }
  }

  // Leave the channel
  Future<void> leaveChannel() async {
    if (!_isInitialized || _engine == null) return;
    try {
      await _engine?.leaveChannel();
    } catch (e) {
      LogService.e('Error leaving channel', e, StackTrace.current);
    }
  }

  // Toggle microphone
  Future<void> toggleMicrophone(bool enabled) async {
    if (!_isInitialized || _engine == null) return;
    try {
      await _engine?.muteLocalAudioStream(!enabled);
    } catch (e) {
      LogService.e('Error toggling microphone', e, StackTrace.current);
    }
  }
}
