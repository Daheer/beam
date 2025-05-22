enum ConnectionRequestStatus { pending, accepted, rejected, expired }

class ConnectionRequest {
  final String id;
  final String senderId;
  final String receiverId;
  final ConnectionRequestStatus status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? senderEmail;
  final String? receiverEmail;
  final bool? hasCalledBefore;
  final DateTime? lastCallAt;

  ConnectionRequest({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.status,
    this.createdAt,
    this.updatedAt,
    this.senderEmail,
    this.receiverEmail,
    this.hasCalledBefore = false,
    this.lastCallAt,
  });

  // Create from Firestore data
  factory ConnectionRequest.fromMap(String id, Map<String, dynamic> map) {
    return ConnectionRequest(
      id: id,
      senderId: map['senderId'] ?? '',
      receiverId: map['receiverId'] ?? '',
      status: ConnectionRequestStatus.values.firstWhere(
        (e) => e.toString().split('.').last == map['status'],
        orElse: () => ConnectionRequestStatus.pending,
      ),
      createdAt: map['createdAt']?.toDate(),
      updatedAt: map['updatedAt']?.toDate(),
      senderEmail: map['senderEmail'],
      receiverEmail: map['receiverEmail'],
      hasCalledBefore: map['hasCalledBefore'] ?? false,
      lastCallAt: map['lastCallAt']?.toDate(),
    );
  }

  // Convert to map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'receiverId': receiverId,
      'status': status.toString().split('.').last,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'senderEmail': senderEmail,
      'receiverEmail': receiverEmail,
      'hasCalledBefore': hasCalledBefore,
      'lastCallAt': lastCallAt,
    };
  }
}
