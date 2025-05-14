import 'dart:convert';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

typedef StreamStateCallback = void Function(MediaStream stream);
typedef ConnectionStateCallback = void Function(RTCPeerConnectionState state);

class SignalingService {
  Map<String, dynamic> configuration = {
    'iceServers': [
      {
        'urls': [
          'stun:stun1.l.google.com:19302',
          'stun:stun2.l.google.com:19302',
        ],
      },
    ],
  };

  RTCPeerConnection? peerConnection;
  MediaStream? localStream;
  MediaStream? remoteStream;
  String? roomId;
  String? currentRoomText;
  StreamStateCallback? onAddRemoteStream;
  ConnectionStateCallback? onConnectionStateChange;
  bool isConnected = false;

  // Track call setup completion
  Completer<void>? _connectionCompleter;

  // Debug mode for verbose logging
  bool _debug = true;

  void _log(String message) {
    if (_debug) {
      print('SignalingService: $message');
    }
  }

  Future<String> createRoom() async {
    _log('Creating new room');
    FirebaseFirestore db = FirebaseFirestore.instance;
    DocumentReference roomRef = db.collection('calls').doc();

    _connectionCompleter = Completer<void>();

    try {
      // Create a new peer connection
      _log('Creating peer connection');
      peerConnection = await createPeerConnection(configuration);
      registerPeerConnectionListeners();

      // Add local tracks to peer connection
      if (localStream != null) {
        _log('Adding local tracks to peer connection');
        localStream!.getTracks().forEach((track) {
          peerConnection?.addTrack(track, localStream!);
        });
      } else {
        _log('Warning: No local stream available when creating room');
      }

      // Code for collecting ICE candidates
      _log('Setting up ICE candidate collection');
      var callerCandidatesCollection = roomRef.collection('callerCandidates');
      peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
        _log('Got caller ICE candidate: ${candidate.candidate}');
        callerCandidatesCollection.add(candidate.toMap());
      };

      // Create a room with offer
      _log('Creating offer');
      RTCSessionDescription offer = await peerConnection!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
      });
      await peerConnection!.setLocalDescription(offer);
      _log('Local description set');

      Map<String, dynamic> roomWithOffer = {
        'offer': offer.toMap(),
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'initiated', // Make sure status is set properly
      };

      _log('Saving room with offer to Firestore');
      await roomRef.set(roomWithOffer);
      roomId = roomRef.id;
      _log('Room created with ID: $roomId');

      // Set up handlers for remote tracks
      peerConnection?.onTrack = (RTCTrackEvent event) {
        _log('Got remote track: ${event.track.kind}');
        event.streams[0].getTracks().forEach((track) {
          _log('Adding track to remote stream: ${track.kind}');
          remoteStream?.addTrack(track);
        });

        // Notify about remote stream addition
        if (onAddRemoteStream != null && event.streams.isNotEmpty) {
          _log('Calling onAddRemoteStream callback');
          onAddRemoteStream!(event.streams[0]);
        }
      };

      // This is also important for older WebRTC implementations
      peerConnection?.onAddStream = (MediaStream stream) {
        _log('Remote stream added with ${stream.getTracks().length} tracks');

        // Call the remote stream callback if set
        if (onAddRemoteStream != null) {
          _log('Calling onAddRemoteStream callback from onAddStream');
          onAddRemoteStream!(stream);
        }

        remoteStream = stream;
      };

      // Listen for remote session description
      _log('Setting up listener for remote description');
      StreamSubscription<DocumentSnapshot>? roomSubscription;
      roomSubscription = roomRef.snapshots().listen(
        (snapshot) async {
          _log('Room data updated');
          if (!snapshot.exists) {
            _log('Room no longer exists');
            roomSubscription?.cancel();
            return;
          }

          Map<String, dynamic> data = snapshot.data() as Map<String, dynamic>;

          // Check if we've already set remote description and there's an answer
          if (peerConnection?.getRemoteDescription() == null &&
              data['answer'] != null) {
            _log('Got remote description from answer');
            try {
              var answer = RTCSessionDescription(
                data['answer']['sdp'],
                data['answer']['type'],
              );
              await peerConnection?.setRemoteDescription(answer);
              _log('Remote description set');

              // Check if we're connected yet
              if (!_connectionCompleter!.isCompleted &&
                  data['status'] == 'connected') {
                _log('Call now connected on caller side');
                if (!isConnected) {
                  isConnected = true;
                  _connectionCompleter?.complete();
                }
              }
            } catch (e) {
              _log('Error setting remote description: $e');
            }
          }

          // Check if call was declined or ended
          if (data['status'] == 'declined' || data['status'] == 'ended') {
            _log('Call was declined or ended');
            if (!_connectionCompleter!.isCompleted) {
              _connectionCompleter?.completeError('Call was declined or ended');
            }
            roomSubscription?.cancel();
          }
        },
        onError: (error) {
          _log('Error listening to room changes: $error');
          if (!_connectionCompleter!.isCompleted) {
            _connectionCompleter?.completeError(error);
          }
        },
      );

      // Listen for remote ICE candidates
      _log('Setting up listener for remote ICE candidates');
      roomRef
          .collection('calleeCandidates')
          .snapshots()
          .listen(
            (snapshot) {
              snapshot.docChanges.forEach((change) {
                if (change.type == DocumentChangeType.added) {
                  _log('Got new remote ICE candidate');
                  Map<String, dynamic> data =
                      change.doc.data() as Map<String, dynamic>;
                  _log('Adding ICE candidate: ${data['candidate']}');
                  peerConnection!.addCandidate(
                    RTCIceCandidate(
                      data['candidate'],
                      data['sdpMid'],
                      data['sdpMLineIndex'],
                    ),
                  );
                }
              });
            },
            onError: (error) {
              _log('Error listening for remote ICE candidates: $error');
            },
          );

      // Wait for connection to be established with timeout
      try {
        // Don't wait for the connection to be established here
        // Just return the room ID and let the UI handle the connection state
        return roomId!;
      } catch (e) {
        if (e is! TimeoutException) {
          _log('Call connection error: $e');
        }
        rethrow;
      }
    } catch (e) {
      _log('Error creating room: $e');
      throw e;
    }
  }

  Future<void> joinRoom(String roomId) async {
    _log('Joining room: $roomId');
    FirebaseFirestore db = FirebaseFirestore.instance;
    DocumentReference roomRef = db.collection('calls').doc(roomId);
    this.roomId = roomId; // Set roomId immediately

    _connectionCompleter = Completer<void>();

    try {
      var roomSnapshot = await roomRef.get();
      _log('Room exists: ${roomSnapshot.exists}');

      if (roomSnapshot.exists) {
        // Create a new peer connection
        _log('Creating peer connection for joining room');
        peerConnection = await createPeerConnection(configuration);
        registerPeerConnectionListeners();

        // Add local tracks to peer connection
        if (localStream != null) {
          _log('Adding local tracks to peer connection');
          localStream!.getTracks().forEach((track) {
            peerConnection?.addTrack(track, localStream!);
          });
        } else {
          _log('Warning: No local stream available when joining room');
        }

        // Code for collecting ICE candidates
        _log('Setting up ICE candidate collection');
        var calleeCandidatesCollection = roomRef.collection('calleeCandidates');
        peerConnection!.onIceCandidate = (RTCIceCandidate? candidate) {
          if (candidate == null) {
            _log('ICE candidate gathering complete');
            return;
          }
          _log('Got callee ICE candidate: ${candidate.candidate}');
          calleeCandidatesCollection.add(candidate.toMap());
        };

        // Set up handlers for remote tracks
        peerConnection?.onTrack = (RTCTrackEvent event) {
          _log('Got remote track');
          event.streams[0].getTracks().forEach((track) {
            _log('Adding track to remote stream: ${track.kind}');
            remoteStream?.addTrack(track);
          });
        };

        // Code for creating SDP answer
        _log('Getting offer from room data');
        var data = roomSnapshot.data() as Map<String, dynamic>;
        var offer = data['offer'];
        _log('Setting remote description with offer');
        await peerConnection?.setRemoteDescription(
          RTCSessionDescription(offer['sdp'], offer['type']),
        );

        _log('Creating answer');
        var answer = await peerConnection!.createAnswer({
          'offerToReceiveAudio': true,
          'offerToReceiveVideo': false,
        });
        _log('Setting local description with answer');
        await peerConnection!.setLocalDescription(answer);

        _log('Saving answer to Firestore');
        Map<String, dynamic> roomWithAnswer = {
          'answer': {'type': answer.type, 'sdp': answer.sdp},
          'status': 'connected',
          'connectedAt': FieldValue.serverTimestamp(),
        };
        await roomRef.update(roomWithAnswer);
        _log('Answer saved to Firestore');

        // Mark as connected on callee side
        isConnected = true;
        _connectionCompleter?.complete();

        // Listen for remote ICE candidates
        _log('Setting up listener for remote ICE candidates');
        roomRef
            .collection('callerCandidates')
            .snapshots()
            .listen(
              (snapshot) {
                snapshot.docChanges.forEach((document) {
                  if (document.type == DocumentChangeType.added) {
                    _log('Got new remote ICE candidate');
                    var data = document.doc.data() as Map<String, dynamic>;
                    _log('Adding ICE candidate: ${data['candidate']}');
                    peerConnection!.addCandidate(
                      RTCIceCandidate(
                        data['candidate'],
                        data['sdpMid'],
                        data['sdpMLineIndex'],
                      ),
                    );
                  }
                });
              },
              onError: (error) {
                _log('Error listening for remote ICE candidates: $error');
              },
            );

        // Monitor call status
        roomRef.snapshots().listen(
          (snapshot) {
            if (snapshot.exists) {
              var data = snapshot.data() as Map<String, dynamic>;
              if (data['status'] == 'ended') {
                _log('Call ended by other party');
                hangUp();
              }
            }
          },
          onError: (error) {
            _log('Error monitoring call status: $error');
          },
        );
      } else {
        _log('Error: Attempted to join non-existent room');
        throw Exception('Room does not exist');
      }
    } catch (e) {
      _log('Error joining room: $e');
      if (!_connectionCompleter!.isCompleted) {
        _connectionCompleter?.completeError(e);
      }
      throw e;
    }
  }

  Future<void> openUserMedia() async {
    _log('Opening user media');
    try {
      var constraints = {
        'audio': true,
        'video': false, // Audio call only
      };

      _log('Getting user media with constraints: $constraints');
      var stream = await navigator.mediaDevices.getUserMedia(constraints);
      _log('Got local stream with ${stream.getTracks().length} tracks');

      // Note: Echo cancellation, noise suppression, and auto gain control
      // are enabled by default in most WebRTC implementations
      _log('Using default audio processing settings');

      localStream = stream;

      _log('Creating remote stream');
      remoteStream = await createLocalMediaStream('remoteStream');
      _log('Media setup complete');
    } catch (e) {
      _log('Error opening user media: $e');
      throw e;
    }
  }

  Future<void> hangUp() async {
    _log('Hanging up call');
    try {
      // Clean up Firestore first (in case peer connection cleanup takes time)
      if (roomId != null) {
        _log('Cleaning up Firestore for room: $roomId');
        var db = FirebaseFirestore.instance;
        var roomRef = db.collection('calls').doc(roomId);

        try {
          _log('Updating room status to ended');
          await roomRef
              .update({
                'status': 'ended',
                'endedAt': FieldValue.serverTimestamp(),
              })
              .timeout(Duration(seconds: 2))
              .catchError((e) => _log('Error updating room status: $e'));
        } catch (e) {
          _log('Failed to update room status: $e');
        }

        // Attempt to clean up ICE candidates, but don't wait if it takes too long
        try {
          await Future.wait([
            _cleanupCandidates(roomRef, 'calleeCandidates'),
            _cleanupCandidates(roomRef, 'callerCandidates'),
          ]).timeout(
            Duration(seconds: 3),
            onTimeout: () {
              _log('ICE candidate cleanup timed out');
              return <void>[];
            },
          );
        } catch (e) {
          _log('Error during ICE candidate cleanup: $e');
        }
      }

      // Stop all tracks on local stream
      if (localStream != null) {
        _log('Stopping local tracks');
        try {
          localStream!.getTracks().forEach((track) {
            _log('Stopping track: ${track.kind}');
            track.stop();
          });
        } catch (e) {
          _log('Error stopping local tracks: $e');
        }
      }

      // Stop all tracks on remote stream
      if (remoteStream != null) {
        _log('Stopping remote tracks');
        try {
          remoteStream!.getTracks().forEach((track) => track.stop());
        } catch (e) {
          _log('Error stopping remote tracks: $e');
        }
      }

      // Close peer connection
      if (peerConnection != null) {
        _log('Closing peer connection');
        try {
          peerConnection!.close();
        } catch (e) {
          _log('Error closing peer connection: $e');
        }
      }

      // Dispose streams
      _log('Disposing streams');
      try {
        localStream?.dispose();
        remoteStream?.dispose();
      } catch (e) {
        _log('Error disposing streams: $e');
      }

      // Clear variables
      peerConnection = null;
      localStream = null;
      remoteStream = null;
      isConnected = false;

      if (_connectionCompleter != null && !_connectionCompleter!.isCompleted) {
        _connectionCompleter!.completeError('Call was ended');
      }

      _log('Hangup complete');
    } catch (e) {
      _log('Error during hangup: $e');
    }
  }

  Future<void> _cleanupCandidates(
    DocumentReference roomRef,
    String collectionName,
  ) async {
    try {
      _log('Deleting $collectionName');
      var candidates = await roomRef
          .collection(collectionName)
          .get()
          .timeout(Duration(seconds: 2));

      // Process in batches to avoid overwhelming Firestore
      List<Future<void>> deleteFutures = [];
      for (var doc in candidates.docs) {
        deleteFutures.add(
          doc.reference.delete().catchError(
            (e) => _log('Error deleting candidate: $e'),
          ),
        );

        // Process in small batches
        if (deleteFutures.length >= 10) {
          await Future.wait(deleteFutures).timeout(
            Duration(milliseconds: 500),
            onTimeout: () {
              _log('Batch delete timed out');
              return <void>[];
            },
          );
          deleteFutures.clear();
        }
      }

      // Delete any remaining candidates
      if (deleteFutures.isNotEmpty) {
        await Future.wait(deleteFutures).timeout(
          Duration(milliseconds: 500),
          onTimeout: () {
            _log('Final batch delete timed out');
            return <void>[];
          },
        );
      }
    } catch (e) {
      _log('Error cleaning up $collectionName: $e');
    }
  }

  void registerPeerConnectionListeners() {
    _log('Registering peer connection listeners');

    peerConnection?.onIceGatheringState = (RTCIceGatheringState state) {
      _log('ICE gathering state changed: $state');
    };

    peerConnection?.onConnectionState = (RTCPeerConnectionState state) {
      _log('Connection state change: $state');

      // Notify about connection state changes
      if (onConnectionStateChange != null) {
        onConnectionStateChange!(state);
      }

      // When connected, mark as connected
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _log('PeerConnection is connected!');
        isConnected = true;
        if (_connectionCompleter != null &&
            !_connectionCompleter!.isCompleted) {
          _connectionCompleter!.complete();
        }
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _log('PeerConnection is disconnected!');
        isConnected = false;
        if (_connectionCompleter != null &&
            !_connectionCompleter!.isCompleted) {
          _connectionCompleter!.completeError('Connection failed: $state');
        }
      }
    };

    peerConnection?.onSignalingState = (RTCSignalingState state) {
      _log('Signaling state change: $state');
    };

    peerConnection?.onIceConnectionState = (RTCIceConnectionState state) {
      _log('ICE connection state change: $state');

      // When ICE connection is complete and connected, mark as connected
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _log('ICE connection is established!');
      }
    };

    peerConnection?.onAddStream = (MediaStream stream) {
      _log('Remote stream added with ${stream.getTracks().length} tracks');

      // Call the remote stream callback if set
      if (onAddRemoteStream != null) {
        _log('Calling onAddRemoteStream callback from onAddStream');
        onAddRemoteStream!(stream);
      }

      remoteStream = stream;
    };
  }
}
