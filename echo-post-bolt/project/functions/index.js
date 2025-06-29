const functions = require('firebase-functions');
const fetch = require('node-fetch');
const Busboy = require('busboy');
const FormData = require('form-data');

exports.tiktokExchange = functions.https.onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  
  if (req.method === 'OPTIONS') {
    // Send response to OPTIONS requests
    res.set('Access-Control-Allow-Methods', 'POST');
    res.set('Access-Control-Allow-Headers', 'Content-Type');
    res.status(204).send('');
    return;
  }
  
  if (req.method !== 'POST') {
    return res.status(405).send('Method Not Allowed');
  }

  try {
    const { auth_code } = req.body;
    
    if (!auth_code) {
      return res.status(400).json({ error: 'Missing auth_code parameter' });
    }

    // Exchange auth code for access token
    const tokenResponse = await fetch(
      'https://open-api.tiktok.com/oauth/access_token/',
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          client_key: process.env.TIKTOK_CLIENT_KEY,
          client_secret: process.env.TIKTOK_CLIENT_SECRET,
          code: auth_code,
          grant_type: 'authorization_code',
        }),
      }
    );

    const tokenData = await tokenResponse.json();
    
    if (tokenData.data.error_code !== 0) {
      return res.status(400).json({
        error: 'TikTok token exchange failed',
        details: tokenData.data,
      });
    }

    return res.status(200).json({
      access_token: tokenData.data.access_token,
      open_id: tokenData.data.open_id,
      expires_in: tokenData.data.expires_in,
    });
  } catch (error) {
    console.error('TikTok token exchange error:', error);
    return res.status(500).json({ error: 'Internal server error' });
  }
});

exports.tiktokUploadAndPublish = functions.https.onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  
  if (req.method === 'OPTIONS') {
    // Send response to OPTIONS requests
    res.set('Access-Control-Allow-Methods', 'POST');
    res.set('Access-Control-Allow-Headers', 'Content-Type');
    res.status(204).send('');
    return;
  }
  
  if (req.method !== 'POST') {
    return res.status(405).send('Method Not Allowed');
  }

  const busboy = new Busboy({ headers: req.headers });
  let accessToken, openId, caption, privacy;
  let videoBuffer; // accumulate chunks of the file
  let videoField = false;

  busboy.on('field', (fieldname, val) => {
    if (fieldname === 'access_token') accessToken = val;
    if (fieldname === 'open_id') openId = val;
    if (fieldname === 'caption') caption = val;
    if (fieldname === 'privacy') privacy = val;
  });

  busboy.on('file', (fieldname, file, filename) => {
    if (fieldname === 'video_file') {
      videoField = true;
      const chunks = [];
      file.on('data', (data) => {
        chunks.push(data);
      });
      file.on('end', () => {
        videoBuffer = Buffer.concat(chunks);
      });
    }
  });

  busboy.on('finish', async () => {
    try {
      if (!accessToken || !openId || !videoBuffer) {
        return res.status(400).json({
          status: 'error',
          message: 'Missing required parameters',
        });
      }

      // 1. Step 1: upload video to TikTok
      const form = new FormData();
      form.append('open_id', openId);
      form.append('video', videoBuffer, {
        filename: 'video.mp4',
        contentType: 'video/mp4',
      });

      const uploadResponse = await fetch(
        'https://open-api.tiktok.com/video/upload/',
        {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${accessToken}`,
          },
          body: form,
        }
      );
      
      const uploadData = await uploadResponse.json();
      if (uploadData.data.error_code !== 0) {
        return res.status(400).json({
          status: 'error',
          message: 'TikTok upload failed: ' + JSON.stringify(uploadData.data),
        });
      }
      
      const videoId = uploadData.data.video_id;

      // 2. Step 2: publish the video
      const publishResponse = await fetch(
        'https://open-api.tiktok.com/video/publish/',
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${accessToken}`,
          },
          body: JSON.stringify({
            open_id: openId,
            video_id: videoId,
            caption: caption,
            privacy_type: privacy || 'PUBLIC',
          }),
        }
      );
      
      const publishData = await publishResponse.json();
      if (publishData.data.error_code !== 0) {
        return res.status(400).json({
          status: 'error',
          message: 'TikTok publish failed: ' + JSON.stringify(publishData.data),
        });
      }

      return res.status(200).json({
        status: 'success',
        video_id: videoId,
      });
    } catch (err) {
      console.error('TikTok upload and publish error:', err);
      return res.status(500).json({
        status: 'error',
        message: err.toString(),
      });
    }
  });

  busboy.end(req.rawBody);
});