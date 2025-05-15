/**
 * Import function triggers from their respective submodules:
 *
 * const {onCall} = require("firebase-functions/v2/https");
 * const {onDocumentWritten} = require("firebase-functions/v2/firestore");
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

const {onRequest} = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");

const functions = require('firebase-functions');
const { RtcTokenBuilder, RtcRole } = require('agora-access-token');

exports.generateAgoraToken = functions.https.onRequest((req, res) => {
  const appId = functions.config().agora.app_id;
  const appCertificate = functions.config().agora.app_certificate;
  const channelName = req.body.channelName;
  const uid = req.body.uid;
  const role = RtcRole.PUBLISHER;
  const expireTime = 3600; // Token valid for 1 hour
  const currentTime = Math.floor(Date.now() / 1000);
  const privilegeExpireTime = currentTime + expireTime;

  const token = RtcTokenBuilder.buildTokenWithUid(
    appId,
    appCertificate,
    channelName,
    uid,
    role,
    privilegeExpireTime
  );

  res.json({ token });
});

