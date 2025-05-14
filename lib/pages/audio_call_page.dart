import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/signaling_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

class AudioCallPage extends StatefulWidget {
  final Map<String, dynamic> professional;
  final bool isIncoming;
  final String? roomId;

  const AudioCallPage({
    Key? key,
    required this.professional,
    this.isIncoming = false,
    this.roomId,
  }) : super(key: key);

  @override
  State<AudioCallPage> createState() => _AudioCallPageState();
}

class _AudioCallPageState extends State<AudioCallPage> {
  final SignalingService _signaling = SignalingService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _isCallActive = false;
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  bool _isConnecting = true;
  bool _hasError = false;
  bool _isEnding = false; // Flag to track call ending state
  String _errorMessage = '';
  String? _roomId;
  Duration _callDuration = Duration.zero;
  StreamSubscription<DocumentSnapshot>? _callStatusSubscription;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _initializeCall();
  }

  Future<void> _initializeCall() async {
    try {
      // Initialize audio
      await _signaling.openUserMedia();

      // Handle remote stream
      _signaling.onAddRemoteStream = (stream) {
        if (mounted) {
          print('Remote stream added, activating call and starting timer');
          setState(() {
            _isCallActive = true;
            _isConnecting = false;
          });
          _startCallTimer();
        }
      };

      // Handle connection state changes
      _signaling.onConnectionStateChange = (state) {
        if (mounted) {
          print('Connection state changed to: $state');
          if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
            print(
              'PeerConnection is connected, activating call and starting timer',
            );
            setState(() {
              _isCallActive = true;
              _isConnecting = false;
              _hasError = false;
            });
            _startCallTimer();
          } else if (state ==
                  RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
              state ==
                  RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
            print('Connection lost or failed: $state');
            if (!_isEnding) {
              // Only show error if not already ending the call
              _setError('Connection lost');
              // Only end call on disconnect - allow reconnection attempts otherwise
              if (state ==
                  RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
                _endCall();
              }
            }
          }
        }
      };

      if (widget.isIncoming && widget.roomId != null) {
        _roomId = widget.roomId;
        setState(() {
          _isConnecting = true;
        });

        try {
          // Check room status first
          DocumentSnapshot roomSnapshot =
              await _firestore.collection('calls').doc(_roomId).get();
          if (!roomSnapshot.exists) {
            throw Exception('Call room no longer exists');
          }

          final data = roomSnapshot.data() as Map<String, dynamic>;
          if (data['status'] == 'ended' || data['status'] == 'declined') {
            throw Exception('Call has already ended');
          }

          // Join the room if incoming call
          print('Joining call room: $_roomId (incoming call)');
          await _signaling.joinRoom(_roomId!);

          // Update call status in Firestore
          await _firestore
              .collection('calls')
              .doc(_roomId)
              .update({
                'status': 'connected',
                'connectedAt': FieldValue.serverTimestamp(),
              })
              .catchError((e) => print('Error updating call status: $e'));

          setState(() {
            _isCallActive = true;
            _isConnecting = false;
          });
          _startCallTimer();
        } catch (e) {
          print('Error joining call: $e');
          if (mounted && !_isEnding) {
            _setError('Failed to join call: $e');
          }
        }
      } else {
        // Create a room for outgoing call
        setState(() {
          _isConnecting = true;
        });

        try {
          print('Creating new call room (outgoing call)');
          _roomId = await _signaling.createRoom();
          print('Created call room: $_roomId');

          // Store call reference in Firestore
          await _storeCallReference();
        } catch (e) {
          print('Error creating call room: $e');
          if (mounted && !_isEnding) {
            _setError('Failed to start call: $e');
          }
        }
      }

      // Setup call status stream
      if (_roomId != null) {
        _setupCallStatusListener();
      }
    } catch (e) {
      print('Call initialization error: $e');
      if (mounted && !_isEnding) {
        _setError('Failed to initialize call: $e');
      }
    }
  }

  void _setupCallStatusListener() {
    // Cancel any existing subscription
    _callStatusSubscription?.cancel();

    // Create a new subscription
    _callStatusSubscription = _firestore
        .collection('calls')
        .doc(_roomId)
        .snapshots()
        .listen(
          (snapshot) {
            if (!mounted || _isEnding) return;

            if (snapshot.exists) {
              final data = snapshot.data() as Map<String, dynamic>;
              print('Call status update: ${data['status']}');

              // Call is now connected
              if (data['status'] == 'connected') {
                print('Firestore status is connected');
                if (!_isCallActive) {
                  print('Activating call based on Firestore connected status');
                  setState(() {
                    _isCallActive = true;
                    _isConnecting = false;
                  });
                  _startCallTimer();
                }
              }

              // Call declined or ended by other party
              if ((data['status'] == 'declined' || data['status'] == 'ended') &&
                  !_isEnding) {
                print('Call was ${data['status']} by the other party');
                if (data['status'] == 'declined') {
                  _setError('Call declined');
                }
                _safeEndCall();
              }
            } else {
              print('Call room no longer exists');
              if (!_isEnding) {
                _safeEndCall();
              }
            }
          },
          onError: (e) {
            print('Error monitoring call status: $e');
          },
        );
  }

  // Safely end the call - won't cause recursive calls
  void _safeEndCall() {
    if (!_isEnding) {
      _endCall();
    }
  }

  Future<void> _storeCallReference() async {
    if (_roomId == null || _auth.currentUser == null) return;

    try {
      // Get the current user's profile data
      DocumentSnapshot userDoc =
          await _firestore
              .collection('users')
              .doc(_auth.currentUser!.uid)
              .get();

      if (!userDoc.exists) {
        print('Error: Current user document not found');
        return;
      }

      Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;

      // Store additional metadata for the call
      await _firestore.collection('calls').doc(_roomId).set({
        'caller': _auth.currentUser!.uid,
        'callerName': userData['name'] ?? 'Unknown User',
        'callerImage': userData['profilePicture'],
        'callee': widget.professional['id'],
        'calleeName': widget.professional['name'] ?? 'Unknown Professional',
        'calleeImage': widget.professional['image'],
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'initiated',
        'type': 'audio',
      }, SetOptions(merge: true));

      print('Call reference stored successfully: $_roomId');
    } catch (e) {
      print('Error storing call reference: $e');
    }
  }

  void _setError(String message) {
    if (mounted) {
      setState(() {
        _hasError = true;
        _errorMessage = message;
        _isConnecting = false;
      });
    }
  }

  void _startCallTimer() {
    // Cancel any existing timer first
    _timer?.cancel();

    // Reset duration if needed
    if (_callDuration.inSeconds == 0) {
      print('Starting call timer from 0:00');
    } else {
      print('Resuming call timer from ${_formatDuration(_callDuration)}');
    }

    // Start a periodic timer to update duration every second
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (mounted && _isCallActive && !_isEnding) {
        setState(() {
          _callDuration = Duration(seconds: _callDuration.inSeconds + 1);
        });
        print('Call duration: ${_formatDuration(_callDuration)}');
      } else if (!mounted || _isEnding) {
        // Stop the timer if the call is no longer active
        timer.cancel();
      }
    });
  }

  void _toggleMute() {
    if (_signaling.localStream != null) {
      _signaling.localStream!.getAudioTracks().forEach((track) {
        track.enabled = !track.enabled;
      });
      setState(() {
        _isMuted = !_isMuted;
      });
    }
  }

  void _toggleSpeaker() async {
    try {
      // Set audio output using helper selectors
      if (_signaling.localStream != null) {
        // Note: On mobile, the proper way to toggle between speaker and earpiece
        // is using the platform-specific APIs which are not directly exposed in flutter_webrtc
        // For now, we'll just update the UI state but in a real implementation
        // you would use a plugin like flutter_webrtc_audio_manager or a native method channel

        print("Toggling speaker mode: ${_isSpeakerOn ? 'Off' : 'On'}");

        // This will be real in production with the appropriate implementation
        setState(() {
          _isSpeakerOn = !_isSpeakerOn;
        });
      }
    } catch (e) {
      print('Error toggling speaker mode: $e');
      setState(() {
        _isSpeakerOn = !_isSpeakerOn;
      });
    }
  }

  Future<void> _endCall() async {
    if (_isEnding) return; // Prevent multiple call ending attempts

    setState(() {
      _isEnding = true;
    });

    print('Ending call...');

    // Stop the timer
    _timer?.cancel();
    _timer = null;

    try {
      // Cancel status subscription
      _callStatusSubscription?.cancel();
      _callStatusSubscription = null;

      // First update the call status in Firestore
      if (_roomId != null) {
        try {
          await _firestore
              .collection('calls')
              .doc(_roomId)
              .update({
                'status': 'ended',
                'endedAt': FieldValue.serverTimestamp(),
                'duration': _callDuration.inSeconds,
              })
              .timeout(Duration(seconds: 3))
              .catchError(
                (e) => print('Error updating call status on end: $e'),
              );
        } catch (e) {
          print('Failed to update call status: $e');
        }
      }

      // Then clean up the connection
      try {
        await _signaling.hangUp().timeout(
          Duration(seconds: 5),
          onTimeout: () {
            print('Hangup timed out, continuing with navigation');
          },
        );
      } catch (e) {
        print('Error during hangup: $e');
      }

      // Make sure we're still mounted before navigating
      if (mounted) {
        // Return to previous screen
        print('Navigating back from call');
        Navigator.of(context).pop();
      }
    } catch (e) {
      print('Error during call end: $e');
      // Still try to navigate even if there was an error
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String minutes = twoDigits(duration.inMinutes.remainder(60));
    String seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }

  @override
  void dispose() {
    print('AudioCallPage: dispose called');
    // Cancel the timer when disposing
    _timer?.cancel();
    _timer = null;

    // Cancel status subscription
    _callStatusSubscription?.cancel();
    _callStatusSubscription = null;

    // End the call if not already ending
    if (!_isEnding) {
      _endCall();
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).colorScheme.primary,
              Theme.of(context).colorScheme.primaryContainer,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Top bar with minimize option
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.keyboard_arrow_down,
                        color: Colors.white,
                      ),
                      onPressed: () {
                        // This would minimize the call UI in a real app
                        Navigator.pop(context);
                      },
                    ),
                    Text(
                      _getCallStatusText(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 48), // Balance the row
                  ],
                ),
              ),

              const Spacer(),

              // Caller info
              Container(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    // Profile image
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        image:
                            widget.professional['image'] != null
                                ? DecorationImage(
                                  image: NetworkImage(
                                    widget.professional['image'],
                                  ),
                                  fit: BoxFit.cover,
                                )
                                : null,
                      ),
                      child:
                          widget.professional['image'] == null
                              ? const Icon(
                                Icons.person,
                                size: 60,
                                color: Colors.white,
                              )
                              : null,
                    ),
                    const SizedBox(height: 20),

                    // Name and profession
                    Text(
                      widget.professional['name'] ?? 'Unknown',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.professional['profession'] ?? '',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white.withOpacity(0.8),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Call status/duration
                    if (_hasError)
                      Text(
                        _errorMessage,
                        style: TextStyle(fontSize: 16, color: Colors.red[300]),
                      )
                    else if (_isConnecting)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(
                              color: Colors.white.withOpacity(0.8),
                              strokeWidth: 2,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            widget.isIncoming ? "Connecting..." : "Calling...",
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.white.withOpacity(0.7),
                            ),
                          ),
                        ],
                      )
                    else
                      Text(
                        _isCallActive
                            ? _formatDuration(_callDuration)
                            : "Calling...",
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white.withOpacity(0.7),
                        ),
                      ),
                  ],
                ),
              ),

              const Spacer(),

              // Call controls
              Padding(
                padding: const EdgeInsets.only(bottom: 40),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Mute button
                    CircleAvatar(
                      radius: 30,
                      backgroundColor:
                          _isMuted
                              ? Colors.white
                              : Colors.white.withOpacity(0.3),
                      child: IconButton(
                        icon: Icon(
                          _isMuted ? Icons.mic_off : Icons.mic,
                          color:
                              _isMuted
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.white,
                        ),
                        onPressed: _toggleMute,
                      ),
                    ),

                    // End call button
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: Colors.red,
                      child: IconButton(
                        icon: const Icon(
                          Icons.call_end,
                          color: Colors.white,
                          size: 30,
                        ),
                        onPressed: _endCall,
                      ),
                    ),

                    // Speaker button
                    CircleAvatar(
                      radius: 30,
                      backgroundColor:
                          _isSpeakerOn
                              ? Colors.white
                              : Colors.white.withOpacity(0.3),
                      child: IconButton(
                        icon: Icon(
                          _isSpeakerOn ? Icons.volume_up : Icons.volume_down,
                          color:
                              _isSpeakerOn
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.white,
                        ),
                        onPressed: _toggleSpeaker,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getCallStatusText() {
    if (_hasError) return "Call Failed";
    if (_isConnecting)
      return widget.isIncoming ? "Connecting..." : "Calling...";
    if (_isCallActive) return "Call in progress";
    return "Calling...";
  }
}
