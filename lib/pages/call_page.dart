import 'package:flutter/material.dart';
import '../services/zego_service.dart';

class CallPage extends StatelessWidget {
  final String callID;
  final String userID;
  final String userName;
  final String targetUserID;
  final String targetUserName;
  final bool isVideoCall;

  const CallPage({
    Key? key,
    required this.callID,
    required this.userID,
    required this.userName,
    required this.targetUserID,
    required this.targetUserName,
    this.isVideoCall = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ZegoService().buildCallPage(
        callID: callID,
        userID: userID,
        userName: userName,
        targetUserID: targetUserID,
        targetUserName: targetUserName,
        isVideoCall: isVideoCall,
      ),
    );
  }
}
