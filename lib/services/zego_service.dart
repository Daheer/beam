import 'package:flutter/material.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ZegoService {
  static final ZegoService _instance = ZegoService._internal();
  factory ZegoService() => _instance;
  ZegoService._internal();

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    final appId = int.parse(dotenv.env['ZEGO_APP_ID'] ?? '0');
    final appSign = dotenv.env['ZEGO_APP_SIGN'] ?? '';

    if (appId == 0 || appSign.isEmpty) {
      throw Exception('ZEGO_APP_ID and ZEGO_APP_SIGN must be set in .env file');
    }

    await ZegoUIKit().init(appID: appId, appSign: appSign);

    _isInitialized = true;
  }

  Widget buildCallPage({
    required String callID,
    required String userID,
    required String userName,
    required String targetUserID,
    required String targetUserName,
    bool isVideoCall = false,
  }) {
    final appId = int.parse(dotenv.env['ZEGO_APP_ID'] ?? '0');
    final appSign = dotenv.env['ZEGO_APP_SIGN'] ?? '';

    return ZegoUIKitPrebuiltCall(
      appID: appId,
      appSign: appSign,
      userID: userID,
      userName: userName,
      callID: callID,
      config:
          isVideoCall
              ? ZegoUIKitPrebuiltCallConfig.oneOnOneVideoCall()
              : ZegoUIKitPrebuiltCallConfig.oneOnOneVoiceCall(),
    );
  }
}
